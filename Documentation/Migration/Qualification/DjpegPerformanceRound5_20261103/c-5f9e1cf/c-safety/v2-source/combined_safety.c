// SPDX-License-Identifier: Apache-2.0
/* Standalone source-only extension: pinned combined DC+AC leaf. */
#include "safety_support.h"
static struct { uint64_t pre[2]; int32_t values[64]; uint64_t post[2]; } output;
static struct { uint64_t pre[2]; SJLIACState value; uint64_t post[2]; } reader_box;
static struct { uint64_t pre[2]; int32_t value; uint64_t post[2]; } predictor_box;
static const int32_t untouched=INT32_C(0x12345678);

static void prepare_output(void) {
 __asan_unpoison_memory_region(&output,sizeof(output));
 for(unsigned i=0;i<2;++i) output.pre[i]=output.post[i]=reader_box.pre[i]=reader_box.post[i]=predictor_box.pre[i]=predictor_box.post[i]=canary;
 for(unsigned i=0;i<64;++i) output.values[i]=untouched;
 __asan_poison_memory_region(output.pre,sizeof(output.pre));
 __asan_poison_memory_region(output.post,sizeof(output.post));
}
static void check_guards(void) {
 __asan_unpoison_memory_region(&output,sizeof(output));
 for(unsigned i=0;i<2;++i) require(output.pre[i]==canary && output.post[i]==canary &&
  reader_box.pre[i]==canary && reader_box.post[i]==canary && predictor_box.pre[i]==canary && predictor_box.post[i]==canary,"combined output/state/predictor canary");
}
static SJLIACStatus check_call(uint8_t *storage,size_t capacity,uint8_t *input,size_t count,
 SJLIACState initial,const Model *dc,const Model *ac,int32_t previous,unsigned precision,
 int expected_status,const int32_t *expected,size_t expected_consumed) {
 prepare_output(); reader_box.value=initial; predictor_box.value=previous;
 poison_input(storage,capacity,input,count);
 SJLIACStatus status=sjli_dct_decode_block(input,count,&reader_box.value,&dc->table,&ac->table,
  ac->lookup,8192,&predictor_box.value,precision,output.values,64);
 __asan_unpoison_memory_region(storage,capacity); check_guards();
 check_state(&reader_box.value,initial.byte_offset,count);
 require(status!=SJLI_AC_INVALID_ARGUMENT && status!=SJLI_AC_CODE_INDEX,"valid combined metadata rejected");
 require((unsigned)status<=SJLI_AC_DC_RANGE,"combined status range");
 if(expected_status>=0) require(status==(SJLIACStatus)expected_status,"combined expected status");
 const int64_t bound=INT64_C(1)<<(precision+2);
 if(output.values[0]==untouched) {
  require(status!=SJLI_AC_OK && predictor_box.value==previous,"DC failure predictor/output sequencing");
  for(unsigned i=0;i<64;++i) require(output.values[i]==untouched,"DC failure changed output");
 } else {
  require(predictor_box.value>=-bound && predictor_box.value<=bound,"reconstructed DC bound");
  require(output.values[0]==(status==SJLI_AC_OK?predictor_box.value:0),"DC slot publication stage");
  for(unsigned i=1;i<64;++i) require(output.values[i]>=-32767 && output.values[i]<=32767,"AC category bound");
 }
 if(status==SJLI_AC_INVALID_WIDTH || status==SJLI_AC_DC_RANGE)
  require(output.values[0]==untouched && predictor_box.value==previous,"DC error mutated prediction");
 if(expected) for(unsigned i=0;i<64;++i) require(output.values[i]==expected[i],"combined encoder output");
 if(expected_consumed!=SIZE_MAX) check_ledger(&reader_box.value,initial.available,expected_consumed);
 record_status(status,initial.available); return status;
}
static void encoded_values(void) {
 const unsigned categories[]={0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,31,32,63,64,127,255};
 for(unsigned table=0;table<3;++table) for(unsigned precision=8;precision<=12;precision+=4) {
  const Model *dc=&dc_models[table],*ac=&models[0]; const int32_t bound=1<<(precision+2);
  const int32_t prior[]={-bound,-bound+1,-1,0,1,bound-1,bound,INT32_MIN,INT32_MAX};
  for(unsigned ci=0;ci<sizeof(categories)/sizeof(categories[0]);++ci) {
   unsigned category=categories[ci],max=category<=16?(1u<<category)-1:0;
   const unsigned magnitudes[]={0,max/2,max/2+1,max};
   for(unsigned mi=0;mi<(category==0 || category>16?1u:4u);++mi) {
    unsigned magnitude=magnitudes[mi]; logical_count=0; put_symbol(dc,category);
    if(category<=16) put(magnitude,category);
    size_t dc_bits=logical_count; put_symbol(ac,0); size_t full_bits=logical_count; pad_bits();
    int32_t difference=(int32_t)magnitude;
    if(category>0 && category<=16 && magnitude<(1u<<(category-1))) difference-=(int32_t)((1u<<category)-1);
    for(unsigned pi=0;pi<sizeof(prior)/sizeof(prior[0]);++pi) for(unsigned available=0;available<=64;++available) {
     uint8_t *input=input_small+16+(available%8); size_t count=pack(input,INPUT_MAX,available);
     SJLIACState state={0,bits_at(0,available),available,0xa9};
     int32_t expected[64]; int64_t reconstructed=(int64_t)prior[pi]+difference;
     SJLIACStatus status=category>16?SJLI_AC_INVALID_WIDTH:
      reconstructed < -bound || reconstructed > bound?SJLI_AC_DC_RANGE:SJLI_AC_OK;
     for(unsigned i=0;i<64;++i) expected[i]=status==SJLI_AC_OK?0:untouched;
     if(status==SJLI_AC_OK) expected[0]=(int32_t)reconstructed;
     size_t consumed=status==SJLI_AC_OK?full_bits:dc_bits;
     check_call(input_small,sizeof(input_small),input,count,state,dc,ac,prior[pi],precision,status,expected,consumed);
     if(status==SJLI_AC_INVALID_WIDTH) require(reader_box.value.marker==category,"invalid width payload");
     ++category_counts[category]; ++known_cases;
    }
   }
  }
 }
}
static void stage_failures(void) {
 int32_t unchanged[64]; for(unsigned i=0;i<64;++i) unchanged[i]=untouched;
 for(unsigned table=0;table<3;++table) for(unsigned category=1;category<=16;++category) {
  const Model *dc=&dc_models[table]; logical_count=0;put_symbol(dc,category);put(1u<<(category-1),category);pad_bits();
  for(unsigned available=0;available<dc->widths[category]+category;++available) {
   SJLIACState state={0,bits_at(0,available),available,0}; delivered_bits[0]=0;
   size_t consumed=available<dc->widths[category]?available:dc->widths[category];
   check_call(input_small,sizeof(input_small),input_small+16,0,state,dc,&models[0],0,12,SJLI_AC_END,unchanged,consumed);++known_cases;
  }
 }
 /* Complete DC, five AC samples, then an incomplete category15 magnitude. */
 logical_count=0;put_symbol(&dc_models[0],1);put(1,1);
 for(unsigned i=0;i<5;++i){put_symbol(&models[0],1);put(1,1);}
 put_symbol(&models[0],15);size_t consumed=logical_count;put(0,4);
 SJLIACState state={0,bits_at(0,(unsigned)logical_count),(uint32_t)logical_count,0};
 int32_t expected[64]={0};for(unsigned i=1;i<=5;++i) expected[i]=1;delivered_bits[0]=0;
 check_call(input_small,sizeof(input_small),input_small+16,0,state,&dc_models[0],&models[0],0,12,SJLI_AC_END,expected,consumed);
 require(predictor_box.value==1,"AC failure did not publish valid DC predictor");++known_cases;
 /* Byte-aligned DC completion followed by each marker class or dangling FF. */
 const uint8_t markers[]={0xd0,0xd7,0xd9,0xc0,0xff,1};
 for(unsigned i=0;i<sizeof(markers)+1;++i){
  logical_count=0;put_symbol(&dc_models[0],3);put(4,3);
  uint8_t *input=input_small+16;input[0]=(uint8_t)bits_at(0,8);input[1]=255;
  size_t count=i<sizeof(markers)?3:2;if(count==3)input[2]=markers[i];map_bytes(input,count);
  state=(SJLIACState){0,0,0,0};memset(expected,0,sizeof(expected));
  check_call(input_small,sizeof(input_small),input,count,state,&dc_models[0],&models[0],0,12,
   count==3?SJLI_AC_MARKER:SJLI_AC_END_AFTER_FF,expected,8);
  require(predictor_box.value==4,"AC marker predictor publication");++known_cases;
 }
 /* Run overflow must stop after its Huffman symbol, before magnitude. */
 logical_count=0;put_symbol(&dc_models[0],1);put(1,1);
 for(unsigned i=0;i<62;++i){put_symbol(&models[6],1);put(1,1);}
 put_symbol(&models[6],0x11);consumed=logical_count;put(1,1);pad_bits();
 for(unsigned available=0;available<=64;++available){
  uint8_t *input=input_small+16+(available%8);size_t count=pack(input,INPUT_MAX,available);
  state=(SJLIACState){0,bits_at(0,available),available,0};memset(expected,0,sizeof(expected));
  expected[0]=1;for(unsigned i=1;i<=62;++i)expected[i]=1;
  check_call(input_small,sizeof(input_small),input,count,state,&dc_models[0],&models[6],0,12,SJLI_AC_OK,expected,consumed);++known_cases;
 }
}
static void encoded_ac_categories(void) {
 /* Independently encoded nonzero AC magnitudes exercise every category on
    both the short combined lookup and the long-code fallback. */
 const unsigned table_indices[]={0,2};
 for(unsigned ti=0;ti<2;++ti)for(unsigned category=0;category<=15;++category){
  const Model *ac=&models[table_indices[ti]],*dc=&dc_models[0];
  int32_t expected[64]={0};expected[0]=1;
  logical_count=0;put_symbol(dc,1);put(1,1);
  if(category){
   unsigned maximum=(1u<<category)-1;const unsigned magnitudes[]={0,maximum/2,maximum/2+1,maximum};
   for(unsigned i=1;i<64;++i){
    unsigned magnitude=magnitudes[i%4];put_symbol(ac,category);put(magnitude,category);
    expected[i]=magnitude<(1u<<(category-1))?(int32_t)magnitude-(int32_t)maximum:(int32_t)magnitude;
   }
  }else put_symbol(ac,0);
  size_t consumed=logical_count;pad_bits();
  for(unsigned available=0;available<=64;++available){
   uint8_t *input=input_small+16+available%8;size_t count=pack(input,INPUT_MAX,available);
   SJLIACState state={0,bits_at(0,available),available,0};
   check_call(input_small,sizeof(input_small),input,count,state,dc,ac,0,12,SJLI_AC_OK,expected,consumed);++known_cases;
  }
 }
}
static void invalid_arguments(void) {
 for(unsigned variant=0;variant<19;++variant){
  prepare_output();reader_box.value=(SJLIACState){0,123,0,0xa9};predictor_box.value=7;
  SJLIACHuffman dc=dc_models[0].table,ac=models[0].table;
  uint8_t byte=0;const void *input=&byte;SJLIACState *state=&reader_box.value;
  const SJLIACHuffman *dcp=&dc,*acp=&ac;const uint32_t *lookup=models[0].lookup;
  int32_t *previous=&predictor_box.value,*destination=output.values;size_t count=1,outputs=64,lookups=8192;unsigned precision=8;
  switch(variant){
   case 0:input=NULL;break;case 1:state=NULL;break;case 2:dcp=NULL;break;case 3:acp=NULL;break;
   case 4:lookup=NULL;break;case 5:previous=NULL;break;case 6:destination=NULL;break;
   case 7:outputs=63;break;case 8:outputs=65;break;case 9:lookups=8191;break;case 10:lookups=8193;break;
   case 11:dc.value_count=257;break;case 12:ac.value_count=257;break;case 13:reader_box.value.available=65;break;
   case 14:reader_box.value.byte_offset=2;break;case 15:reader_box.value.byte_offset=SIZE_MAX;break;
   case 16:precision=0;break;case 17:precision=9;break;default:precision=UINT_MAX;break;
  }
  SJLIACState initial=reader_box.value;SJLIACStatus status=sjli_dct_decode_block(input,count,state,dcp,acp,lookup,lookups,previous,precision,destination,outputs);
  check_guards();require(status==SJLI_AC_INVALID_ARGUMENT,"invalid combined arguments accepted");
  require(same_state(&initial,&reader_box.value)&&predictor_box.value==7,"invalid combined arguments changed state");
  for(unsigned i=0;i<64;++i)require(output.values[i]==untouched,"invalid combined arguments changed output");
  record_status(status,65);++guard_cases;
 }
}
static void random_and_boundaries(void) {
 for(unsigned model=0;model<TABLES;++model)for(size_t count=0;count<=17;++count)
  for(size_t offset=0;offset<=count;++offset)for(unsigned available=0;available<=64;++available){
   unsigned alignment=(unsigned)(cases%8);uint8_t *input=input_small+16+alignment;
   pattern(input,count,(unsigned)(count+offset+available+model));
   SJLIACState state={offset,random64(),available,0xa9};
   check_call(input_small,sizeof(input_small),input,count,state,&dc_models[model%3],&models[model],0,model&1?12:8,-1,NULL,SIZE_MAX);++boundary_cases;
  }
 for(unsigned i=0;i<RANDOM_CASES;++i){
  unsigned available=(i/TABLES)%65,precision=(i&1)?12:8,alignment=(i/65)%8;
  size_t count=(size_t)(random64()%(INPUT_MAX+1)),offset=(size_t)(random64()%(count+1));
  uint8_t *storage=(i%8==0)?(uint8_t *)(void *)input_words:input_small;
  uint8_t *input=storage+16+alignment;pattern(input,count,i/(TABLES*65));
  int32_t bound=1<<(precision+2),previous=(int32_t)(random64()%(unsigned)(2*bound+1))-bound;
  SJLIACState state={offset,random64(),available,0xa9};
  check_call(storage,sizeof(input_small),input,count,state,&dc_models[i%3],&models[i%TABLES],previous,precision,-1,NULL,SIZE_MAX);++random_cases;
 }
}
int main(void) {
 random_state=UINT64_C(0xdca18b3725e6409f);make_models();make_dc_models();
 invalid_arguments();encoded_values();encoded_ac_categories();stage_failures();random_and_boundaries();
 require(status_counts[SJLI_AC_OK]&&status_counts[SJLI_AC_DC_RANGE]&&status_counts[SJLI_AC_INVALID_WIDTH]&&status_counts[SJLI_AC_END]&&status_counts[SJLI_AC_MARKER],"combined status coverage");
 for(unsigned i=0;i<=64;++i)require(available_counts[i],"combined missing available-bit width");
 print_counters("combined DC+AC","0xdca18b3725e6409f",9);return 0;
}
