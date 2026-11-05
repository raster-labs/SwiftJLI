#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Deterministic, source-backed corrections to preserved f548 SwiftPM SBOMs."""
import argparse
import copy
import gzip
import hashlib
import importlib.metadata
import json
import re
import sys
import uuid
from collections import Counter
from pathlib import Path
from urllib.parse import urlparse

from jsonschema.validators import validator_for
from referencing import Registry, Resource
from rdflib import Graph
from pyshacl import validate as shacl_validate
from packageurl import PackageURL

PIN = "f548e5048e5c71204c2a2ec4036bf66c4f040285"
URL = "https://github.com/raster-labs/SwiftJLI"
PACKAGE_PURL = "pkg:swift/github.com/raster-labs/SwiftJLI@" + PIN
ICC_SHA = "384b832de3412066743b52a75ee906b6fb9fb8d9e09e936fc2c43223815c6e0a"
ICC_URL = "https://registry.color.org/profile-library/"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--evidence", required=True, type=Path)
parser.add_argument("--inputs", required=True, type=Path)
parser.add_argument("--output", required=True, type=Path)
parser.add_argument("--product", required=True, choices=("SwiftJLI", "swiftjli-cli"))
parser.add_argument("--raw-sbom", type=Path)
args = parser.parse_args()
evidence, inputs, out = (p.resolve() for p in (args.evidence, args.inputs, args.output))
if out.exists():
    parser.error("Existing derived evidence must be preserved; choose a fresh output directory")
def sha(data):
    return hashlib.sha256(data).hexdigest()
def load(path):
    return json.loads(path.read_bytes())
def emit(name, value):
    path = out / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    return sha(path.read_bytes())
capture = load(inputs / "receipt.json")
assert capture["revision"] == PIN and capture["binaryUnchanged"] is True
for entry in capture["files"]:
    assert sha((inputs / entry["path"]).read_bytes()) == entry["sha256"], entry["path"]
raw_root = (args.raw_sbom or (evidence / "sbom")).resolve()
raw_report = load(raw_root / "report.json")
product_id = "urn:spdx:swiftjli:" + args.product
originals = {}
raw_paths = {}
for spec in ("spdx", "cyclonedx"):
    paths = list((raw_root / spec).glob("*.json"))
    assert len(paths) == 1
    raw_paths[spec] = paths[0]
    originals[spec] = load(paths[0])
assert raw_report["candidateRevision"] == PIN
assert raw_report.get("product", "SwiftJLI") == args.product
raw_hashes = {key: sha(p.read_bytes()) for key, p in raw_paths.items()}
helper_hash = sha(Path(__file__).read_bytes())
source = inputs / "source"
assert (source / "LICENSE").read_text().lstrip().startswith("Apache License")
assert "Copyright 2026 Raster Images Private Limited" in (source / "NOTICE").read_text()
icc = (source / "Documentation/Migration/Fixtures/sRGB2014.icc").read_bytes()
assert sha(icc) == ICC_SHA
provenance = load(source / "Documentation/Migration/provenance.json")
asset = next(x for x in provenance["thirdPartyAssets"] if x["sha256"] == ICC_SHA)
assert asset["embeddedSwift"] == "Sources/SwiftJLI/Native/ColorSpace/SRGBICCProfile.swift"
swift = (source / asset["embeddedSwift"]).read_text()
# The literal data array is the binary profile, not the unrelated generated XYB profile.
array = re.search(r"static let data: \[UInt8\] = \[(.*?)\]", swift, re.S)
assert array
assert bytes(int(x) for x in re.findall(r"\d+", array[1])) == icc
icc_notice = (source / "Documentation/Migration/Fixtures/ICC-LICENSE.txt").read_text()
timestamp = max(capture["capturedUTC"], raw_report["finishedUTC"]).split(".")[0] + "Z"
out.mkdir(parents=True, exist_ok=False)

spdx = copy.deepcopy(originals["spdx"])
graph = spdx["@graph"]
packages = [x for x in graph if x["type"] == "software_Package"]
assert len(packages) == 2
for item in packages:
    assert item["software_internalVersion"] == PIN
    item["software_packageVersion"] = item.pop("software_internalVersion")
    original_purl = item.pop("externalUrl")
    item["comment"] = "Derived correction; original SwiftPM package URL: " + original_purl
    item["software_homePage"] = URL
    if item["spdxId"] == "urn:spdx:swiftjli":
        item["software_packageUrl"] = PACKAGE_PURL
    else:
        # A product is not a separately resolvable Swift package. Preserve its ID,
        # source revision and raw URL in the comment rather than invent a purl.
        assert item["spdxId"] == product_id
        item["software_sourceInfo"] = args.product + " product from " + URL + "/tree/" + PIN
for item in graph:
    if item["type"] == "CreationInfo":
        if item["specVersion"] != "3.0.1":
            assert item["specVersion"] == "6.4.2"
            item["comment"] = "Derived correction: SwiftPM wrote its tool version 6.4.2 in SPDX specVersion."
            item["specVersion"] = "3.0.1"

ci_id = "_:derivedCreationInfo"
agent_id = "urn:swiftjli:milestone5:sbom-qualification-agent"
tool_id = "urn:swiftjli:milestone5:derive:" + helper_hash
icc_id = "urn:sha256:" + ICC_SHA
icc_license_id = "urn:swiftjli:licence:icc-profile-terms"
tool_package_id = "urn:swiftjli:build-tool:swift-package-manager:6.4.2"
def element(type_, id_, **values):
    return {"type": type_, "spdxId": id_, "creationInfo": ci_id, **values}
graph.extend([
    {"type": "CreationInfo", "@id": ci_id, "created": timestamp,
     "createdBy": [agent_id], "createdUsing": [tool_id], "specVersion": "3.0.1"},
    element("Agent", agent_id, name="SwiftJLI Milestone 5 SBOM qualification"),
    element("Tool", tool_id, name="derive.py", comment="SHA-256 " + helper_hash),
    element("software_Package", tool_package_id, name="swift-package-manager",
            software_packageVersion="6.4.2", software_primaryPurpose="application",
            comment="Build tool identified by the preserved generator metadata; not a runtime package dependency."),
    element("software_File", icc_id, name="sRGB2014.icc", contentType="application/vnd.iccprofile",
            software_copyrightText="Copyright International Color Consortium, 2015",
            verifiedUsing=[{"type": "Hash", "algorithm": "sha256", "hashValue": ICC_SHA}],
            comment="Unchanged embedded profile; provenance source " + asset["source"]),
    element("simplelicensing_LicenseExpression", icc_license_id,
            simplelicensing_licenseExpression="LicenseRef-ICC-Profile",
            simplelicensing_customIdToUri=[{"type": "DictionaryEntry", "key": "LicenseRef-ICC-Profile", "value": ICC_URL}],
            comment="Repository ICC notice is retained separately; this profile is not relicensed as Apache-2.0."),
])
# SPDX's hasDeclaredLicense must originate at a SoftwareArtifact, not its Agent.
tool_license = graph[0]
assert tool_license["relationshipType"] == "hasDeclaredLicense"
assert any(x.get("spdxId") == tool_license["from"] and x["type"] == "Agent" and x.get("name") == "swift-package-manager" for x in graph)
tool_license["from"] = tool_package_id
tool_license["creationInfo"] = ci_id
tool_license["comment"] = "Corrected licence subject from the creator Agent to its represented software tool; original assertion retained."
for item in packages:
    item["creationInfo"] = ci_id
    graph.append(element("Relationship", item["spdxId"] + "-declared-apache2-derived",
                         **{"from": item["spdxId"], "to": ["urn:spdx:Apache-2.0"], "relationshipType": "hasDeclaredLicense",
                            "comment": "Apache-2.0 covers in-house source; the separately identified embedded ICC asset retains its own terms."}))
graph.extend([
    element("Relationship", "urn:swiftjli:contains:icc-profile", **{"from": product_id, "to": [icc_id], "relationshipType": "contains"}),
    element("Relationship", "urn:swiftjli:icc-profile:declared-licence", **{"from": icc_id, "to": [icc_license_id], "relationshipType": "hasDeclaredLicense"}),
])
document = next(x for x in graph if x["type"] == "SpdxDocument")
document["spdxId"] = "urn:uuid:" + str(uuid.uuid5(uuid.NAMESPACE_URL, document["spdxId"] + "#swiftjli-m5-derived-v1-" + helper_hash))
document["creationInfo"] = ci_id
document["comment"] = "Separately labelled derived release-package SBOM. Raw SPDX SHA-256: " + raw_hashes["spdx"] + ". Native linkage and licence scope: supplement.json."
for item in graph:
    if "profileConformance" in item:
        item["profileConformance"] = ["core", "software", "simpleLicensing"]

cdx = copy.deepcopy(originals["cyclonedx"])
subject = cdx["metadata"]["component"]
duplicates = [x for x in cdx["components"] if x["bom-ref"] == subject["bom-ref"]]
assert duplicates == [subject]
cdx["components"] = [x for x in cdx["components"] if x["bom-ref"] != subject["bom-ref"]]
cdx["version"] += 1
cdx["serialNumber"] = "urn:uuid:" + str(uuid.uuid5(uuid.NAMESPACE_URL, cdx["serialNumber"] + "#derived-" + helper_hash))
cdx["metadata"]["timestamp"] = timestamp
cdx["metadata"]["tools"]["components"].append({"type": "application", "name": "SwiftJLI derived SBOM helper",
    "version": helper_hash, "bom-ref": tool_id, "scope": "excluded", "licenses": [{"license": {"id": "Apache-2.0"}}]})
cdx["metadata"]["properties"] = [
    {"name": "swiftjli:derivation", "value": "derived-v1; raw SHA-256 " + raw_hashes["cyclonedx"]},
    {"name": "swiftjli:inventory-scope", "value": "SwiftPM package/product plus embedded ICC profile; observed consumer-native linkage is in supplement.json. Complete platform runtime/SDK inventory is not claimed."},
]
for item in [subject, *cdx["components"]]:
    assert item["version"] == PIN
    old_purl = item.pop("purl")
    item.setdefault("properties", []).append({"name": "swiftjli:original-generator-purl", "value": old_purl})
    item["properties"].append({"name": "swiftjli:licence-scope", "value": "Apache-2.0 in-house source; embedded ICC profile is separately licensed."})
    item["licenses"] = [{"license": {"id": "Apache-2.0"}}]
    item["externalReferences"] = [{"type": "vcs", "url": URL + "/tree/" + PIN}]
    if item["bom-ref"] == "swiftjli":
        item["purl"] = PACKAGE_PURL
cdx["components"].append({"type": "file", "name": "sRGB2014.icc", "bom-ref": icc_id,
    "hashes": [{"alg": "SHA-256", "content": ICC_SHA}],
    "copyright": "Copyright International Color Consortium, 2015",
    "licenses": [{"license": {"name": "ICC profile terms", "url": ICC_URL}}],
    "externalReferences": [{"type": "distribution", "url": asset["source"]}],
    "description": "Unchanged 3024-byte ICC profile embedded in SRGBICCProfile.swift; not Apache-relicensed."})
cdx["dependencies"].append({"ref": subject["bom-ref"], "dependsOn": [icc_id]})
cdx["dependencies"].append({"ref": icc_id, "dependsOn": []})

native_root = raw_root if args.product == "swiftjli-cli" else inputs
observed_binary = raw_report["binary"] if args.product == "swiftjli-cli" else capture["observedBinary"]
link_lines = (native_root / "native-linkage.stdout").read_text().splitlines()[1:]
links = []
for line in link_lines:
    match = re.fullmatch(r"\s*(.+?) \(compatibility version ([^,]+), current version ([^,)]+)(, weak)?\)", line)
    assert match, line
    links.append({"installName": match[1], "compatibilityVersion": match[2],
                  "loadCommandCurrentVersion": match[3], "weak": bool(match[4]),
                  "licence": "not established from Mach-O metadata", "providedBy": "Apple platform install name"})
supplement = {"revision": PIN, "rawHashes": raw_hashes,
    "licences": {"inHouse": {"declaredSPDX": "Apache-2.0", "sourceLicenceSHA256": sha((source / "LICENSE").read_bytes()),
                              "noticeSHA256": sha((source / "NOTICE").read_bytes())},
                 "embeddedProfile": {"sha256": ICC_SHA, "licenceURL": ICC_URL, "notice": icc_notice,
                                     "noticeSHA256": sha(icc_notice.encode()), "embeddedBytesMatch": True}},
    "swiftPMDependencies": [], "packageManifestSHA256": sha((source / "Package.swift").read_bytes()),
    "product": args.product, "observedExecutable": observed_binary,
    "observedExecutableRole": "qualified SwiftJLI independent consumer" if args.product == "SwiftJLI" else "SBOM-associated swiftjli-cli build", "nativeLoadCommands": links,
    "hostOS": (inputs / "host-os.stdout").read_text(), "sdkVersion": (inputs / "sdk-version.stdout").read_text().strip(),
    "sdkBuild": (inputs / "sdk-build.stdout").read_text().strip(),
    "limits": ["Native entries are the identified release executable's load commands, not a claim that every entry is attributable solely to the SwiftJLI library.",
               "Mach-O current/compatibility versions are linker metadata, not independently verified runtime release versions.",
               "No runtime dylib bytes, transitive system graph or complete SDK contents were inventoried; Apple runtime licences remain externally governed and are not guessed.",
               "System paths indicate platform-provided linkage, not bundled copies. Weak links are explicitly marked.",
               "Test fixtures, oracle containers and external reference codecs are development-only and are outside this library-product SBOM; their retained provenance is separate."]}

def diff(before, after, path=""):
    if type(before) is not type(after):
        return [{"op": "replace", "path": path, "before": before, "value": after}]
    if isinstance(before, dict):
        changes = []
        for k in sorted(before.keys() | after.keys()):
            p = path + "/" + k.replace("~", "~0").replace("/", "~1")
            if k not in after: changes.append({"op": "remove", "path": p, "before": before[k]})
            elif k not in before: changes.append({"op": "add", "path": p, "value": after[k]})
            else: changes.extend(diff(before[k], after[k], p))
        return changes
    if before != after:
        return [{"op": "replace", "path": path, "before": before, "value": after}]
    return []
outputs = {"spdx": spdx, "cyclonedx": cdx}
output_hashes = {spec: emit(spec + ".derived.json", document) for spec, document in outputs.items()}
emit("supplement.json", supplement)
emit("transformations.json", {spec: diff(originals[spec], outputs[spec]) for spec in outputs})

schemas = evidence / "sbom/schemas"
names = {"spdx-json-schema.json", "bom-1.7.schema.json", "spdx.schema.json", "jsf-0.82.schema.json"}
def schema_bytes(name):
    assert name in names
    return gzip.decompress((schemas / (name + ".gz")).read_bytes())
def retrieve(uri):
    return Resource.from_contents(json.loads(schema_bytes(urlparse(uri).path.rsplit("/", 1)[-1])))
registry = Registry(retrieve=retrieve)
schema_results = []
for spec, name in (("spdx", "spdx-json-schema.json"), ("cyclonedx", "bom-1.7.schema.json")):
    schema = json.loads(schema_bytes(name)); validator = validator_for(schema)
    validator.check_schema(schema)
    errors = list(validator(schema, registry=registry, format_checker=validator.FORMAT_CHECKER).iter_errors(outputs[spec]))
    schema_results.append({"format": spec, "schemaSHA256": sha(schema_bytes(name)), "passed": not errors,
        "errors": [{"path": list(e.path), "message": e.message} for e in errors]})
emit("schema-validation.json", schema_results)

context = json.loads(gzip.decompress((inputs / "official/spdx-context.jsonld.gz").read_bytes()))
ontology = gzip.decompress((inputs / "official/spdx-model.ttl.gz").read_bytes())
data = copy.deepcopy(spdx); data["@context"] = context["@context"]
rdf = Graph().parse(data=json.dumps(data), format="json-ld")
model = Graph().parse(data=ontology, format="turtle")
conforms, report_graph, report_text = shacl_validate(rdf, shacl_graph=model, ont_graph=model,
    inference="none", allow_infos=False, allow_warnings=False, advanced=True)
(out / "spdx-shacl.txt").write_text(report_text)
(out / "spdx-shacl.ttl").write_text(report_graph.serialize(format="turtle"))

# Checks independent of JSON Schema: unique identities, resolved references,
# exact revisions and canonical Swift package namespace; raw identities retained.
ids = [x.get("spdxId", x.get("@id")) for x in graph]
assert len(ids) == len(set(ids))
assert all(x["specVersion"] == "3.0.1" for x in graph if x["type"] == "CreationInfo")
for item in graph:
    for key in ("from", "to", "rootElement", "creationInfo", "createdBy", "createdUsing"):
        if key in item:
            references = item[key] if isinstance(item[key], list) else [item[key]]
            assert all(x in ids for x in references), (key, references)
refs = []
def visit(value):
    if isinstance(value, dict):
        if "bom-ref" in value: refs.append(value["bom-ref"])
        for child in value.values(): visit(child)
    elif isinstance(value, list):
        for child in value: visit(child)
visit(cdx)
assert len(refs) == len(set(refs))
assert all(x["ref"] in refs and all(y in refs for y in x["dependsOn"]) for x in cdx["dependencies"])
purl = PackageURL.from_string(PACKAGE_PURL)
assert (purl.type, purl.namespace, purl.name, purl.version) == ("swift", "github.com/raster-labs", "SwiftJLI", PIN)
assert purl.to_string() == PACKAGE_PURL
assert {x["spdxId"] for x in packages} == {x["spdxId"] for x in originals["spdx"]["@graph"] if x["type"] == "software_Package"}
assert {x["bom-ref"] for x in originals["cyclonedx"]["components"]} <= set(refs)
for spec, path in raw_paths.items(): assert sha(path.read_bytes()) == raw_hashes[spec]
passed = bool(conforms) and all(x["passed"] for x in schema_results)
receipt = {"status": "passed" if passed else "failed", "revision": PIN, "product": args.product, "helperSHA256": helper_hash,
    "inputReceiptSHA256": sha((inputs / "receipt.json").read_bytes()), "rawFiles": {k: str(v) for k,v in raw_paths.items()},
    "rawHashesUnchanged": raw_hashes, "derivedHashes": output_hashes,
    "validatorVersions": {n: importlib.metadata.version(n) for n in ("jsonschema", "referencing", "pyshacl", "rdflib", "packageurl-python")},
    "spdxSHACLConforms": bool(conforms), "officialModelSHA256": sha(ontology),
    "semanticChecks": {"uniqueSPDXIdentifiers": True, "SPDXReferencesResolve": True, "SPDXSpecVersions": "3.0.1",
                       "uniqueCycloneDXReferences": True, "CycloneDXDependenciesResolve": True,
                       "originalPackageProductIdentitiesPreserved": True, "candidateRevisionsPreserved": True,
                       "canonicalSwiftPackageURL": PACKAGE_PURL, "embeddedICCBytesMatch": True},
    "scope": "Derived build-associated SwiftPM package and selected product SBOMs with explicit third-party asset and native-linkage supplement; not complete platform inventory or raw-generator conformance."}
emit("receipt.json", receipt)
print(json.dumps({"status": receipt["status"], "jsonSchema": [{"format": x["format"], "passed": x["passed"], "errors": len(x["errors"])} for x in schema_results], "SHACL": bool(conforms)}))
sys.exit(0 if passed else 1)
