// SPDX-License-Identifier: Apache-2.0
/* Exact composed code-zero row: independent encoded corpus, generic differential and alias metamorphic checks. */
#include "safety_support.h"
enum { MAX_SAMPLES=65535, ROW_BYTES=MAX_SAMPLES*2 };
static uint8_t input_large[LARGE_INPUT+64];
static uint32_t output_words[(ROW_BYTES+128)/4],reference_words[(ROW_BYTES+128)/4];
static uint64_t differential_cases,codezero_categories[8];
static uint16_t expected_samples[MAX_SAMPLES];
static size_t symbol_ends[MAX_SAMPLES],sample_ends[MAX_SAMPLES];
static struct { uint64_t pre[2]; SJLIACState value; uint64_t post[2]; } reader_box;
static struct { uint64_t pre[2]; SJLILosslessRowResult value; uint64_t post[2]; } result_box;
static uint8_t alias_a[512],alias_b[512],alias_c[512],alias_snapshot[512];

/* Only this entrypoint is under primary test. The generic composed row is
   a separately called differential oracle, not an independent decoder. */
static SJLIACStatus row_call(const void *input,size_t input_count,SJLIACState *state,
 const SJLIACHuffman *table,uint32_t seed,size_t count,void *output,size_t output_count,
 SJLILosslessRowResult *result) {
 if(table && table->lengths[0]==1 && table->symbols[0]>=1 && table->symbols[0]<=7)
  ++codezero_categories[table->symbols[0]];
 return sjli_lossless_left_u16_code0_row(input,input_count,state,table,seed,count,output,output_count,result);
}
static uint16_t sample_at(const uint8_t *bytes,size_t index) {
 return (uint16_t)((unsigned)bytes[index*2]|((unsigned)bytes[index*2+1]<<8));
}
static SJLIACStatus check_call(uint8_t *storage,size_t capacity,uint8_t *input,size_t input_count,
 SJLIACState initial,const Model *model,uint32_t seed,size_t count,unsigned alignment,
 int expected_status,const uint16_t *expected,size_t expected_written,size_t expected_consumed) {
 require(count>=1&&count<=MAX_SAMPLES&&seed<=65535&&alignment<8,"row harness extents");
 uint8_t *out_storage=(uint8_t *)(void *)output_words,*output=out_storage+16+alignment;
 uint8_t *ref_storage=(uint8_t *)(void *)reference_words,*reference=ref_storage+16+alignment;
 size_t out_capacity=count*2+64;
 __asan_unpoison_memory_region(ref_storage,out_capacity);memset(ref_storage,0xa5,out_capacity);
 __asan_unpoison_memory_region(out_storage,out_capacity);memset(out_storage,0xa5,out_capacity);
 for(unsigned i=0;i<2;++i)reader_box.pre[i]=reader_box.post[i]=result_box.pre[i]=result_box.post[i]=canary;
 reader_box.value=initial;result_box.value=(SJLILosslessRowResult){0xface,0xbeef,0x12345678};
 poison_input(storage,capacity,input,input_count);poison_input(out_storage,out_capacity,output,count*2);
 poison_input(ref_storage,out_capacity,reference,count*2);
 SJLIACState reference_state=initial;SJLILosslessRowResult reference_result={0xface,0xbeef,0x12345678};
 SJLIACStatus status=row_call(input,input_count,&reader_box.value,&model->table,seed,count,output,count*2,&result_box.value);
 SJLIACStatus reference_status=sjli_lossless_left_u16_row(input,input_count,&reference_state,&model->table,seed,count,reference,count*2,&reference_result);
 __asan_unpoison_memory_region(storage,capacity);__asan_unpoison_memory_region(out_storage,out_capacity);
 __asan_unpoison_memory_region(ref_storage,out_capacity);
 require(status==reference_status && same_state(&reader_box.value,&reference_state),"code-zero/generic status and complete reader state");
 require(result_box.value.first==reference_result.first && result_box.value.last==reference_result.last && result_box.value.written==reference_result.written,"code-zero/generic published result");
 require(memcmp(out_storage,ref_storage,out_capacity)==0,"code-zero/generic output and canaries");++differential_cases;
 for(unsigned i=0;i<2;++i)require(reader_box.pre[i]==canary&&reader_box.post[i]==canary&&result_box.pre[i]==canary&&result_box.post[i]==canary,"row state/result canary");
 check_state(&reader_box.value,initial.byte_offset,input_count);
 require((unsigned)status<=SJLI_AC_INVALID_WIDTH&&status!=SJLI_AC_INVALID_ARGUMENT&&status!=SJLI_AC_CODE_INDEX,"valid row state/table rejected");
 if(expected_status>=0)require(status==(SJLIACStatus)expected_status,"row expected status");
 const size_t written=result_box.value.written;
 require(written<=count && (status==SJLI_AC_OK?written==count:written<count),"row written count");
 if(expected_written!=SIZE_MAX)require(written==expected_written,"row independent completed-prefix count");
 if(!written)require(result_box.value.first==0&&result_box.value.last==0,"empty row failure result");
 else require(result_box.value.first==sample_at(output,0)&&result_box.value.last==sample_at(output,written-1),"row first/last result");
 for(size_t i=0;i<out_capacity;++i){
  size_t first=(size_t)(output-out_storage),end=first+written*2;
  if(i<first||i>=end)require(out_storage[i]==0xa5,"row changed bytes outside complete-sample prefix");
 }
 if(expected)for(size_t i=0;i<written;++i)require(sample_at(output,i)==expected[i],"row independently encoded sample");
 if(expected_consumed!=SIZE_MAX)check_ledger(&reader_box.value,initial.available,expected_consumed);
 if(status==SJLI_AC_INVALID_WIDTH)require(reader_box.value.marker>16,"row invalid width payload");
 record_status(status,initial.available);return status;
}
static int32_t difference(unsigned category,unsigned magnitude) {
 if(category==0)return 0;if(category==16)return -32768;
 return magnitude<(1u<<(category-1))?(int32_t)magnitude-(int32_t)((1u<<category)-1):(int32_t)magnitude;
}
static void encode_sample(const Model *model,unsigned category,unsigned magnitude,size_t index) {
 put_symbol(model,category);symbol_ends[index]=logical_count;
 if(category>0&&category<16)put(magnitude,category);
 sample_ends[index]=logical_count;
}
static void category_rows(void) {
 const unsigned seeds[]={0,1,2048,32767,32768,65534,65535};
 for(unsigned table=0;table<DC_MODELS;++table)for(unsigned category=0;category<=16;++category){
  const Model *model=&dc_models[table];unsigned maximum=category>0&&category<16?(1u<<category)-1:0;
  const unsigned magnitudes[]={0,maximum/2,maximum/2+1,maximum};
  logical_count=0;for(size_t i=0;i<17;++i)encode_sample(model,category,magnitudes[i%4],i);
  size_t consumed=logical_count;pad_bits();
  for(unsigned si=0;si<sizeof(seeds)/sizeof(seeds[0]);++si){
   uint32_t value=seeds[si];for(size_t i=0;i<17;++i){value=(value+(uint32_t)difference(category,magnitudes[i%4]))&65535;expected_samples[i]=(uint16_t)value;}
   for(unsigned available=0;available<=64;++available){
    uint8_t *input=input_small+16+available%8;size_t count=pack(input,INPUT_MAX,available);
    SJLIACState state={0,bits_at(0,available),available,0xa9};
    check_call(input_small,sizeof(input_small),input,count,state,model,seeds[si],17,available%8,SJLI_AC_OK,expected_samples,17,consumed);
    ++category_counts[category];++known_cases;
   }
  }
 }
}
static unsigned mixed_category(size_t index){const unsigned cats[]={0,1,16,15};return cats[index%4];}
static unsigned mixed_magnitude(size_t index,unsigned category){return category>0&&category<16 && (index/4)%2 ?(1u<<category)-1:0;}
static void mixed_row(const Model *model,size_t count){
 logical_count=0;for(size_t i=0;i<count;++i){unsigned cat=mixed_category(i);encode_sample(model,cat,mixed_magnitude(i,cat),i);}pad_bits();
}
static void expected_mixed(size_t count,unsigned seed){
 uint32_t value=seed;for(size_t i=0;i<count;++i){unsigned cat=mixed_category(i);value=(value+(uint32_t)difference(cat,mixed_magnitude(i,cat)))&65535;expected_samples[i]=(uint16_t)value;}
}
static void length_boundaries(void) {
 const size_t lengths[]={1,2,3,7,8,9,63,64,65,255,256,257,65534,65535};
 const unsigned seeds[]={0,32768,65535},buffered[]={0,7,8,13,63,64};
 for(unsigned table=0;table<DC_MODELS;table+=2)for(unsigned li=0;li<sizeof(lengths)/sizeof(lengths[0]);++li){
  size_t samples=lengths[li];const Model *model=&dc_models[table];mixed_row(model,samples);
  for(unsigned si=0;si<3;++si){expected_mixed(samples,seeds[si]);
   for(unsigned ai=0;ai<6;++ai){unsigned available=buffered[ai];uint8_t *input=input_large+16+available%8;
    size_t count=pack(input,LARGE_INPUT,available);SJLIACState state={0,bits_at(0,available),available,0};
    check_call(input_large,count+64,input,count,state,model,seeds[si],samples,available%8,SJLI_AC_OK,expected_samples,samples,sample_ends[samples-1]);++known_cases;
   }
  }
 }
}
static void failures_and_truncation(void) {
 const unsigned invalid[]={17,31,32,63,64,127,255};
 for(unsigned table=0;table<DC_MODELS;++table){const Model *model=&dc_models[table];
  for(unsigned bad=0;bad<sizeof(invalid)/sizeof(invalid[0]);++bad){
   logical_count=0;for(size_t i=0;i<5;++i){encode_sample(model,1,1,i);expected_samples[i]=(uint16_t)(32769+i);}
   put_symbol(model,invalid[bad]);size_t consumed=logical_count;pad_bits();
   for(unsigned available=0;available<=64;++available){uint8_t *input=input_small+16+available%8;size_t count=pack(input,INPUT_MAX,available);
    SJLIACState state={0,bits_at(0,available),available,0};
    check_call(input_small,sizeof(input_small),input,count,state,model,32768,9,available%8,SJLI_AC_INVALID_WIDTH,expected_samples,5,consumed);
    require(reader_box.value.marker==invalid[bad],"row invalid category marker");++category_counts[invalid[bad]];++known_cases;
   }
  }
  mixed_row(model,68);expected_mixed(68,32768);
  for(unsigned available=0;available<=64;available+=8){uint8_t *input=input_large+16;size_t full_count=pack(input,LARGE_INPUT,available);
   for(size_t count=0;count<=full_count;++count){
    map_bytes(input,count);size_t total=available+delivered_bits[count],written=0;
    while(written<68&&sample_ends[written]<=total)++written;
    size_t consumed=written==68?sample_ends[67]:symbol_ends[written]<total?symbol_ends[written]:total;
    SJLIACStatus status=written==68?SJLI_AC_OK:(count&&input[count-1]==255?SJLI_AC_END_AFTER_FF:SJLI_AC_END);
    SJLIACState state={0,bits_at(0,available),available,0};
    check_call(input_large,full_count+64,input,count,state,model,32768,68,available%8,status,expected_samples,written,consumed);++known_cases;
   }
  }
 }
}
static void invalid_arguments(void) {
 for(unsigned variant=0;variant<22;++variant){
  uint8_t input_byte=0,bytes[16];memset(bytes,0xa5,sizeof(bytes));
  SJLIACState state={0,123,0,0xa9};SJLILosslessRowResult result={1,2,3};SJLIACHuffman table=dc_models[0].table;
  const void *input=&input_byte;void *output=bytes;SJLIACState *statep=&state;SJLILosslessRowResult *resultp=&result;const SJLIACHuffman *tablep=&table;
  uint32_t seed=0;size_t input_count=1,count=3,output_count=sizeof(bytes);
  switch(variant){
   case 0:input=NULL;break;case 1:output=NULL;break;case 2:statep=NULL;break;case 3:resultp=NULL;break;case 4:tablep=NULL;break;
   case 5:seed=65536;break;case 6:seed=UINT32_MAX;break;case 7:count=0;break;case 8:count=65536;break;case 9:count=SIZE_MAX;break;
   case 10:output_count=5;break;case 11:table.value_count=257;break;case 12:state.available=65;break;
   case 13:state.byte_offset=2;break;case 14:state.byte_offset=SIZE_MAX;break;case 15:output_count=0;break;case 16:state.available=UINT32_MAX;break;
   case 17:table.lengths[0]=0;break;case 18:table.lengths[0]=2;break;case 19:table.symbols[0]=0;break;
   case 20:table.symbols[0]=8;break;default:table.symbols[0]=255;break;
  }
  SJLIACState initial=state;SJLIACStatus status=row_call(input,input_count,statep,tablep,seed,count,output,output_count,resultp);
  require(status==SJLI_AC_INVALID_ARGUMENT&&same_state(&state,&initial),"row invalid argument/state");
  require(result.first==1&&result.last==2&&result.written==3,"row invalid argument changed result");
  for(unsigned i=0;i<sizeof(bytes);++i)require(bytes[i]==0xa5,"row invalid argument changed output");
  record_status(status,65);++guard_cases;
 }
}
static void aliases(void) {
 const int deltas[]={-16,-1,0,1,16,80};
 for(unsigned trial=0;trial<10000;++trial){
  for(unsigned i=0;i<sizeof(alias_a);++i)alias_a[i]=(uint8_t)random64();
  size_t input_start=64+trial%8,input_count=(size_t)(random64()%129),samples=1+(trial%DC_MODELS2);
  size_t output_start=(size_t)((int)input_start+deltas[trial%6]);
  pattern(alias_a+input_start,input_count,trial/65);memcpy(alias_b,alias_a,sizeof(alias_a));memcpy(alias_snapshot,alias_a,sizeof(alias_a));memcpy(alias_c,alias_a,sizeof(alias_a));
  size_t lower=input_start<output_start?input_start:output_start;
  size_t upper=input_start+input_count>output_start+samples*2?input_start+input_count:output_start+samples*2;
  __asan_poison_memory_region(alias_a,lower);__asan_poison_memory_region(alias_b,lower);__asan_poison_memory_region(alias_c,lower);
  __asan_poison_memory_region(alias_a+upper,sizeof(alias_a)-upper);__asan_poison_memory_region(alias_b+upper,sizeof(alias_b)-upper);__asan_poison_memory_region(alias_c+upper,sizeof(alias_c)-upper);
  SJLIACState a={(size_t)(random64()%(input_count+1)),random64(),trial%65,0xa9},b=a,c=a;
  size_t start=a.byte_offset;uint32_t seed=(uint32_t)(random64()&65535),value=seed;SJLILosslessRowResult ar={0},br={0},cr={0};
  const Model *model=&dc_models[trial%DC_MODELS];
  SJLIACStatus ast=row_call(alias_a+input_start,input_count,&a,&model->table,seed,samples,alias_a+output_start,samples*2,&ar),bst=SJLI_AC_OK;
  SJLIACStatus cst=sjli_lossless_left_u16_row(alias_c+input_start,input_count,&c,&model->table,seed,samples,alias_c+output_start,samples*2,&cr);
  for(size_t i=0;i<samples;++i){SJLILosslessRowResult single={0};
   bst=row_call(alias_b+input_start,input_count,&b,&model->table,value,1,alias_b+output_start+i*2,2,&single);
   if(bst!=SJLI_AC_OK)break;if(i==0)br.first=single.first;br.last=single.last;br.written+=1;value=single.last;
  }
  __asan_unpoison_memory_region(alias_a,sizeof(alias_a));__asan_unpoison_memory_region(alias_b,sizeof(alias_b));__asan_unpoison_memory_region(alias_c,sizeof(alias_c));
  require(ast==cst&&same_state(&a,&c),"aliased code-zero/generic status and reader state");
  require(ar.first==cr.first&&ar.last==cr.last&&ar.written==cr.written,"aliased code-zero/generic result");
  require(memcmp(alias_a,alias_c,sizeof(alias_a))==0,"aliased code-zero/generic complete buffer");++differential_cases;
  require(ast==bst&&same_state(&a,&b),"row alias one-row/one-sample state equivalence");
  require(ar.first==br.first&&ar.last==br.last&&ar.written==br.written,"row alias partial result equivalence");
  require(memcmp(alias_a,alias_b,sizeof(alias_a))==0,"row alias byte equivalence");check_state(&a,start,input_count);
  require(ar.written<=samples,"row alias prefix bound");
  for(size_t i=0;i<sizeof(alias_a);++i)if(i<output_start||i>=output_start+ar.written*2)
   require(alias_a[i]==alias_snapshot[i],"row alias changed bytes outside written prefix");
  if(ar.written)require(ar.first==sample_at(alias_a+output_start,0)&&ar.last==sample_at(alias_a+output_start,ar.written-1),"row alias first/last bytes");
  record_status(ast,trial%65);++alias_cases;
 }
}
static void random_and_boundaries(void) {
 for(unsigned model=0;model<DC_MODELS;++model)for(size_t count=0;count<=17;++count)
  for(size_t offset=0;offset<=count;++offset)for(unsigned available=0;available<=64;++available){
   uint8_t *input=input_small+16+cases%8;pattern(input,count,(unsigned)(count+offset+available+model));
   SJLIACState state={offset,random64(),available,0xa9};
   check_call(input_small,sizeof(input_small),input,count,state,&dc_models[model%DC_MODELS],32768,9,available%8,-1,NULL,SIZE_MAX,SIZE_MAX);++boundary_cases;
  }
 for(unsigned i=0;i<RANDOM_CASES;++i){
  unsigned available=(i/TABLES)%65,alignment=(i/65)%8;size_t count=(size_t)(random64()%(INPUT_MAX+1));
  uint8_t *storage=i%8==0?(uint8_t *)(void *)input_words:input_small,*input=storage+16+alignment;
  pattern(input,count,i/(TABLES*65));SJLIACState state={(size_t)(random64()%(count+1)),random64(),available,0xa9};
  check_call(storage,sizeof(input_small),input,count,state,&dc_models[i%DC_MODELS],(uint32_t)(random64()&65535),1+i%32,alignment,-1,NULL,SIZE_MAX,SIZE_MAX);++random_cases;
 }
}
static void every_short_prefix(void) {
 for(unsigned model=0;model<DC_MODELS;++model)for(unsigned prefix=0;prefix<256;++prefix)for(unsigned tail=0;tail<8;++tail){
  uint8_t *input=input_small+16+tail;pattern(input,17,prefix+model);
  SJLIACState state={tail%3,((uint64_t)prefix<<tail)|((UINT64_C(1)<<tail)-1),8+tail,0xa9};
  check_call(input_small,sizeof(input_small),input,17,state,&dc_models[model],32768,9,tail,-1,NULL,SIZE_MAX,SIZE_MAX);++boundary_cases;
 }
}
int main(void) {
 random_state=UINT64_C(0xc0d0187a9b56e243);make_models();make_dc_models();
 invalid_arguments();category_rows();length_boundaries();failures_and_truncation();aliases();every_short_prefix();random_and_boundaries();
 require(status_counts[SJLI_AC_OK]&&status_counts[SJLI_AC_INVALID_WIDTH]&&status_counts[SJLI_AC_END]&&status_counts[SJLI_AC_MARKER],"row status coverage");
 for(unsigned i=0;i<=64;++i)require(available_counts[i],"row missing available-bit width");
 for(unsigned category=1;category<=7;++category)require(codezero_categories[category],"missing first-code-zero category");
 require(differential_cases+guard_cases==cases,"missing generic differential case");
 print_counters("composed code-zero lossless row","0xc0d0187a9b56e243",8);return 0;
}
