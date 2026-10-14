// Persistent OpenUSD authoring service. One JSON request/response per line.
// Source layers are read-only; authoring opinions go to owned local layers.
#include <pxr/pxr.h>
#include <pxr/base/js/json.h>
#include <pxr/base/tf/errorMark.h>
#include <pxr/base/gf/matrix4d.h>
#include <pxr/base/gf/vec2d.h>
#include <pxr/base/gf/vec3d.h>
#include <pxr/base/gf/vec3h.h>
#include <pxr/base/vt/array.h>
#include <pxr/base/gf/quatd.h>
#include <pxr/base/gf/quatf.h>
#include <pxr/base/ts/spline.h>
#include <pxr/base/ts/knot.h>
#include <pxr/usd/sdf/reference.h>
#include <pxr/usd/sdf/payload.h>
#include <pxr/usd/sdf/timeCode.h>
#include <pxr/usd/usd/stage.h>
#include <pxr/usd/usd/primRange.h>
#include <pxr/usd/usd/variantSets.h>
#include <pxr/usd/usdGeom/xformable.h>
#include <pxr/usd/usdGeom/xformCache.h>
#include <pxr/usd/usdGeom/metrics.h>
#include <pxr/usd/usdShade/shader.h>
#include <pxr/usd/usdUtils/dependencies.h>
#include <pxr/usd/usdUtils/flattenLayerStack.h>
#include <pxr/usd/usdUtils/usdzPackage.h>
#include <filesystem>
#include "usd-camera.h"
#include <fstream>
#include <iostream>
#include <cmath>
#include <algorithm>
#include <set>
#include <map>
#include <limits>
#include <unistd.h>
#include <fcntl.h>
#include <random>
#include <pxr/usd/ar/packageUtils.h>
#include <pxr/usd/pcp/primIndex.h>
#include <pxr/usd/pcp/layerStack.h>
PXR_NAMESPACE_USING_DIRECTIVE
namespace fs = std::filesystem;
using Object = JsObject;
static std::string newIdentity() {
  std::random_device random; const char *hex="0123456789abcdef"; std::string id="atlas:";
  for(int i=0;i<16;++i) { unsigned byte=random()&255; id+=hex[byte>>4]; id+=hex[byte&15]; }
  return id;
}
static void emit(const JsValue &v) { { JsWriter writer(std::cout); JsWriteValue(&writer,v); } std::cout << std::endl; }
static const JsValue &field(const Object &o, const std::string &k) {
  auto i=o.find(k); if(i==o.end()) throw std::runtime_error("Missing field: "+k); return i->second;
}
static std::string string(const JsValue &v) {
  if(!v.IsString()) throw std::runtime_error("Expected string"); return v.GetString();
}
static double number(const JsValue &v) {
  double n=v.IsReal()?v.GetReal():v.IsInt()?double(v.GetInt64()):NAN;
  if(!std::isfinite(n)) throw std::runtime_error("Expected finite number"); return n;
}
static bool boolean(const JsValue &v) {
  if(!v.IsBool()) throw std::runtime_error("Expected boolean"); return v.GetBool();
}
static double sampleTime(const Object &o) {
  double time=o.count("time")?number(field(o,"time")):0;
  if(std::abs(time)>1e9) throw std::runtime_error("Time exceeds supported range (+/- 1e9 time codes)");
  return time;
}
static bool validIdentity(const std::string &id) {
  return !id.empty() && id.size()<=128 && std::none_of(id.begin(),id.end(),[](unsigned char c){return c<32 || c==127;});
}
#include "usd-numeric.h"
static JsValue value(const VtValue &v) {
  if(numericValue(v)){auto numbers=numericComponents(v);for(double n:numbers)if(!std::isfinite(n))throw std::runtime_error("Non-finite authored numeric value");if(numbers.size()==1)return JsValue(numbers[0]);JsArray out;for(double n:numbers)out.emplace_back(n);return JsValue(out);}
  if(v.IsHolding<float>()) return JsValue(double(v.UncheckedGet<float>()));
  if(v.IsHolding<double>()) return JsValue(v.UncheckedGet<double>());
  if(v.IsHolding<int>()) return JsValue(v.UncheckedGet<int>());
  if(v.IsHolding<bool>()) return JsValue(v.UncheckedGet<bool>());
  if(v.IsHolding<TfToken>()) return JsValue(v.UncheckedGet<TfToken>().GetString());
  if(v.IsHolding<std::string>()) return JsValue(v.UncheckedGet<std::string>());
  if(v.IsHolding<SdfAssetPath>()) { const auto &a=v.UncheckedGet<SdfAssetPath>();
    return JsValue(Object{{"asset",JsValue(a.GetAssetPath())},{"resolved",JsValue(a.GetResolvedPath())}}); }
  if(v.IsHolding<GfVec3f>()) { auto a=v.UncheckedGet<GfVec3f>(); return JsValue(JsArray{JsValue(double(a[0])),JsValue(double(a[1])),JsValue(double(a[2]))}); }
  if(v.IsHolding<GfVec2f>()) { auto a=v.UncheckedGet<GfVec2f>(); return JsValue(JsArray{JsValue(double(a[0])),JsValue(double(a[1]))}); }
  return JsValue();
}
static JsValue matrix(const GfMatrix4d &m) {
  JsArray a; for(int r=0;r<4;++r) for(int c=0;c<4;++c) {if(!std::isfinite(m[r][c]))throw std::runtime_error("Non-finite composed transform");a.emplace_back(m[r][c]);} return JsValue(a);
}
#include "usd-workspace.h"
class Session {
  UsdStageRefPtr stage;
  std::string source;
  int revision=0;
  size_t primLimit=100000;
  struct AuthorLayer { std::string name; SdfLayerRefPtr layer; };
  std::vector<AuthorLayer> authorLayers;
  std::string targetName="session";
  std::string workspacePath,workspaceGeneration,savedState,openedSourceHash;
  JsArray workspaceDependencies;
  struct WorkingLayer { std::string original,sha256; SdfLayerRefPtr layer; };
  std::vector<WorkingLayer> workingLayers;
  JsArray workingDependencies;
  std::string targetContext;
  int targetNode=-1;
  struct History { std::string session,target,context,sourceHash; int node=-1; SdfLayerRefPtr root,sessionHandle;
    std::vector<std::pair<std::string,std::string>> layers; std::vector<SdfLayerRefPtr> handles;
    std::vector<WorkingLayer> working;std::vector<std::string> workingTexts;JsArray dependencies,workingDependencies;UsdStageLoadRules rules; };
  std::vector<History> undoHistory,redoHistory;
  SdfLayerHandle target() { return stage->GetEditTarget().GetLayer(); }
  History capture() {
    History h;stage->GetSessionLayer()->ExportToString(&h.session);h.target=targetName;h.rules=stage->GetLoadRules();
    h.root=stage->GetRootLayer();h.sessionHandle=stage->GetSessionLayer();h.working=workingLayers;h.context=targetContext;h.node=targetNode;h.sourceHash=openedSourceHash;h.dependencies=workspaceDependencies;h.workingDependencies=workingDependencies;
    size_t bytes=h.session.size();
    for(const auto &a:authorLayers) {std::string text;a.layer->ExportToString(&text);bytes+=text.size();h.layers.emplace_back(a.name,text);h.handles.push_back(a.layer);}
    for(const auto &a:workingLayers){std::string text;a.layer->ExportToString(&text);bytes+=text.size();h.workingTexts.push_back(text);}
    if(bytes>32*1024*1024)throw std::runtime_error("Authoring layers exceed 32 MiB history limit");
    return h;
  }
  // Anonymous sublayer identifiers vary across processes; fingerprint opinions,
  // names, order, target and literal payload rules instead of those identifiers.
  std::string stateHash() {
    auto session=SdfLayer::CreateAnonymous();session->TransferContent(stage->GetSessionLayer());session->SetSubLayerPaths({});
    std::string text;session->ExportToString(&text);JsArray layers,rules,working;
    for(const auto &a:authorLayers){std::string content;a.layer->ExportToString(&content);layers.emplace_back(Object{{"name",JsValue(a.name)},{"content",JsValue(content)}});}
    for(const auto &r:stage->GetLoadRules().GetRules())rules.emplace_back(JsArray{JsValue(r.first.GetString()),JsValue(int(r.second))});
    for(size_t i=0;i<workingLayers.size();++i){auto clone=SdfLayer::CreateAnonymous();clone->TransferContent(workingLayers[i].layer);
      workspace::repath(clone,[&](const std::string &path){for(size_t j=0;j<workingLayers.size();++j)if(path==workingLayers[j].layer->GetIdentifier())return "working:"+std::to_string(j);return path;});
      std::string content;clone->ExportToString(&content);working.emplace_back(content);}
    return workspace::digest(workspace::json(JsValue(Object{{"session",JsValue(text)},{"layers",JsValue(layers)},{"target",JsValue(targetName)},{"rules",JsValue(rules)},
      {"working",JsValue(working)},{"source_pins",JsValue(workingDependencies)},{"context",JsValue(targetContext)},{"node",JsValue(targetNode)}})));
  }
  #include "usd-working-layers.h"
  #include "usd-identities.h"
  void select(const std::string &name) {
    if(name.rfind("working:",0)==0){selectWorking(name,"",-1);return;}
    targetContext.clear();targetNode=-1;
    if(name=="session")stage->SetEditTarget(stage->GetSessionLayer());
    else {
      auto found=std::find_if(authorLayers.begin(),authorLayers.end(),[&](const AuthorLayer &a){return a.name==name;});
      if(found==authorLayers.end())throw std::runtime_error("Unknown local authoring layer");
      stage->SetEditTarget(found->layer);
    }
    targetName=name;
  }
  void restore(const History &h) {
    // Keep handles alive and reuse identifiers so no-op rollback is observably unchanged.
    std::vector<AuthorLayer> restored;std::vector<std::string> paths;size_t index=0;
    for(const auto &entry:h.layers) {
      auto layer=h.handles[index++];
      if(!layer->ImportFromString(entry.second))throw std::runtime_error("Cannot restore authoring layer");
      restored.push_back({entry.first,layer});paths.push_back(layer->GetIdentifier());
    }
    workingLayers=h.working;
    for(size_t i=0;i<workingLayers.size();++i)if(!workingLayers[i].layer->ImportFromString(h.workingTexts[i]))throw std::runtime_error("Cannot restore source working copy");
    if(!h.sessionHandle->ImportFromString(h.session))throw std::runtime_error("Cannot restore session history");
    h.sessionHandle->SetSubLayerPaths(paths);authorLayers=std::move(restored);
    stage=UsdStage::Open(h.root,h.sessionHandle,UsdStage::LoadNone);stage->SetLoadRules(h.rules);
    openedSourceHash=h.sourceHash;workspaceDependencies=h.dependencies;workingDependencies=h.workingDependencies;
    if(h.target.rfind("working:",0)==0)selectWorking(h.target,h.context,h.node);else select(h.target);
  }
  void remember(std::vector<History> &history,const History &h) {
    history.push_back(h);size_t bytes=0;
    for(const auto &entry:history) {bytes+=entry.session.size();for(const auto &layer:entry.layers)bytes+=layer.second.size();for(const auto &text:entry.workingTexts)bytes+=text.size();}
    while(history.size()>32 || bytes>64*1024*1024) {
      bytes-=history.front().session.size();for(const auto &layer:history.front().layers)bytes-=layer.second.size();for(const auto &text:history.front().workingTexts)bytes-=text.size();history.erase(history.begin());
    }
  }
  void valid() {
    if(!stage) throw std::runtime_error("Open a stage first");
    if(!stage->GetCompositionErrors().empty()) throw std::runtime_error("USD composition contains errors");
    size_t count=0; for(auto p:stage->TraverseAll()) if(++count>primLimit) throw std::runtime_error("Loaded stage exceeds prim budget");
  }
  UsdPrim prim(const Object &o,bool editable=true) {
    SdfPath p(string(field(o,"path")));
    if(!p.IsAbsolutePath() || !p.IsPrimPath()) throw std::runtime_error("Expected absolute prim path");
    auto result=stage->GetPrimAtPath(p);
    if(!result || (editable && result.IsInstanceProxy())) throw std::runtime_error("Missing prim or instance proxy is not editable");
    if(editable && stage->GetEditTarget().MapToSpecPath(p).IsEmpty())throw std::runtime_error("Prim is outside the selected source edit context");
    return result;
  }
  void seedSamples(const UsdAttribute &a) {
    // Editing a source spec must not copy stronger composed opinions into it.
    if(targetName.rfind("working:",0)==0)return;
    if(!target()->ListTimeSamplesForPath(stage->GetEditTarget().MapToSpecPath(a.GetPath())).empty())return;
    if(a.GetNumTimeSamples()>10000)throw std::runtime_error("Attribute exceeds 10000 editable keys");
    std::vector<double> times;a.GetTimeSamples(&times);
    // A stronger layer's time-sample map replaces the weaker map as a whole.
    // Copy the composed curve before its first session edit to retain other keys.
    std::vector<VtValue> values;
    for(double t:times) {VtValue v;if(!a.Get(&v,UsdTimeCode(t)))throw std::runtime_error("Cannot read curve key");values.push_back(v);}
    for(size_t i=0;i<times.size();++i)if(!a.Set(values[i],UsdTimeCode(times[i])))throw std::runtime_error("Cannot seed curve overrides");
  }
  #include "usd-curve-authoring.h"
  #include "usd-animation-authoring.h"
  JsValue snapshot(double time) {
    valid(); UsdGeomXformCache cache{UsdTimeCode(time)}; JsArray prims,layers,payloads,usedLayers;
    std::map<std::string,JsArray> identities; JsArray identityIssues;
    for(auto layer:stage->GetLayerStack()) {
      std::string name=layer==stage->GetSessionLayer()?"session":"";
      for(const auto &a:authorLayers)if(a.layer==layer)name=a.name;
      for(size_t i=0;i<workingLayers.size();++i)if(workingLayers[i].layer==layer)name="working:"+std::to_string(i);
      layers.emplace_back(Object{{"identifier",JsValue(layer->GetIdentifier())},{"anonymous",JsValue(layer->IsAnonymous())},
        {"name",JsValue(name)},{"editable",JsValue(!name.empty())},{"selected",JsValue(layer==target())}});
    }
    // GetUsedLayers has no stable order, including after a rejected edit's
    // rollback. Expose a canonical path set for snapshots and file watchers.
    std::set<std::string> usedLayerPaths;
    for(auto l:stage->GetUsedLayers()) if(!l->IsAnonymous()) usedLayerPaths.insert(l->GetRealPath());
    for(const auto &copy:workingLayers)usedLayerPaths.insert(copy.original);
    for(const auto &path:usedLayerPaths)usedLayers.emplace_back(path);
    for(auto p:stage->TraverseAll()) {
      Object variants; for(const auto &name:p.GetVariantSets().GetNames()) {
        auto set=p.GetVariantSet(name); JsArray names; for(auto v:set.GetVariantNames()) names.emplace_back(v);
        variants[name]=JsValue(Object{{"selected",JsValue(set.GetVariantSelection())},{"choices",JsValue(names)}});
      }
      Object row{{"id",JsValue(p.GetPath().GetString())},{"type",JsValue(p.GetTypeName().GetString())},
        {"active",JsValue(p.IsActive())},{"loaded",JsValue(p.IsLoaded())},{"instance",JsValue(p.IsInstance())},
        {"variants",JsValue(variants)}};
      auto identity=p.GetCustomDataByKey(TfToken("atlas:uuid"));
      if(identity.IsHolding<std::string>()) row["stable_id"]=JsValue(identity.UncheckedGet<std::string>());
      if(p.IsAbstract() || !p.IsDefined()) row["identity_status"]=JsValue("template");
      else if(identity.IsEmpty()) row["identity_status"]=JsValue("missing");
      else if(!identity.IsHolding<std::string>() || !validIdentity(identity.UncheckedGet<std::string>())) {
        row["identity_status"]=JsValue("invalid");
        identityIssues.emplace_back(Object{{"kind",JsValue("invalid")},{"path",JsValue(p.GetPath().GetString())}});
      } else { row["identity_status"]=JsValue("authored"); identities[identity.UncheckedGet<std::string>()].emplace_back(p.GetPath().GetString()); }
      UsdGeomImageable imageable(p);
      if(imageable) row["visibility"]=JsValue(imageable.ComputeVisibility(UsdTimeCode(time)).GetString());
      if(p.IsInstance()) row["prototype"]=JsValue(p.GetPrototype().GetPath().GetString());
      if(p.HasPayload()) payloads.emplace_back(p.GetPath().GetString());
      if(UsdGeomXformable(p)) row["world_transform_row_major"]=matrix(cache.GetLocalToWorldTransform(p));
      const auto type=p.GetTypeName().GetString();
      if(type=="Camera") row["atlas_camera"]=atlasCamera(p,time);
      if(type=="Camera" || type.find("Light")!=std::string::npos || type=="Shader") {
        Object attributes;
        for(auto a:p.GetAttributes()) {
          VtValue v; if(a.Get(&v,UsdTimeCode(time))) {
            auto encoded=value(v); if(!encoded.IsNull()) attributes[a.GetName().GetString()]=encoded;
          }
        }
        row["attributes"]=JsValue(attributes);
      }
      prims.emplace_back(row);
    }
    for(const auto &entry:identities) if(entry.second.size()>1)
      identityIssues.emplace_back(Object{{"kind",JsValue("duplicate")},{"stable_id",JsValue(entry.first)},{"paths",JsValue(entry.second)}});
    return JsValue(Object{{"source",JsValue(source)},{"openusd_version",JsValue(PXR_VERSION)},
      {"workspace",JsValue(workspacePath)},{"workspace_generation",JsValue(workspaceGeneration)},
      {"unsaved_changes",JsValue(workspacePath.empty() || stateHash()!=savedState)},
      {"identity_issues",JsValue(identityIssues)},{"edit_target",JsValue(targetName)},
      {"working_layers",workingSnapshot()},{"source_conflicts",JsValue(sourceConflicts())},{"edit_context",JsValue(targetContext)},{"edit_node",JsValue(targetNode)},
      {"revision",JsValue(revision)},{"undo_count",JsValue(int(undoHistory.size()))},{"redo_count",JsValue(int(redoHistory.size()))},{"time",JsValue(time)},{"prims",JsValue(prims)},
      {"layers",JsValue(layers)},{"used_layers",JsValue(usedLayers)},{"payloads",JsValue(payloads)},
      {"meters_per_unit",JsValue(UsdGeomGetStageMetersPerUnit(stage))},
      {"up_axis",JsValue(UsdGeomGetStageUpAxis(stage).GetString())},
      {"time_codes_per_second",JsValue(stage->GetTimeCodesPerSecond())},
      {"start",JsValue(stage->GetStartTimeCode())},{"end",JsValue(stage->GetEndTimeCode())}});
  }
  #include "usd-workspace-session.h"
  void dependencyBudget(const std::string &file) {
    std::vector<SdfLayerRefPtr> layers; std::vector<std::string> assets,missing;
    if(!UsdUtilsComputeAllDependencies(SdfAssetPath(file),&layers,&assets,&missing) || !missing.empty())
      throw std::runtime_error("Package has unresolved dependencies");
    std::set<std::string> files;
    for(auto l:layers) if(!l->IsAnonymous()) files.insert(l->GetRealPath());
    files.insert(assets.begin(),assets.end());
    uintmax_t bytes=0;
    if(files.size()>4096) throw std::runtime_error("Package exceeds dependency count budget");
    for(auto f:files) { auto size=fs::file_size(f); bytes+=size;
      if(size>64*1024*1024 || bytes>256*1024*1024) throw std::runtime_error("Package exceeds byte budget"); }
  }
  JsValue save(const Object &o, const std::string &op) {
    TfErrorMark errors;
    fs::path target=fs::absolute(string(field(o,"destination"))).lexically_normal();
    if(fs::exists(target)) throw std::runtime_error("Export destination already exists");
    if(!fs::is_directory(target.parent_path())) throw std::runtime_error("Export parent directory does not exist");
    auto extension=target.extension().string();
    if((op=="package" && extension!=".usdz") || (op!="package" && extension!=".usda" && extension!=".usdc" && extension!=".usd"))
      throw std::runtime_error("Invalid USD export extension");
    fs::path temp=target.parent_path()/(".atlas-"+std::to_string(getpid())+"-"+target.filename().string());
    fs::path overlay=temp.string()+".usda";
    fs::path sourceDirectory;
    if(fs::exists(temp)||fs::exists(overlay)) throw std::runtime_error("Temporary export path already exists");
    try {
      if(op=="flatten" || op=="preview") {
        if(op=="flatten") for(auto p:stage->TraverseAll())
          if(p.HasPayload() && !p.IsLoaded()) throw std::runtime_error("Load all payloads before flattening; otherwise their contents would be lost");
        if(op=="preview" && o.count("animated") && boolean(field(o,"animated")))for(auto p:stage->TraverseAll())for(auto a:p.GetAttributes())
          if(a.HasSpline())throw std::runtime_error("Explicitly bake spline "+a.GetPath().GetString()+" before sampled runtime preview; USD/USDZ delivery preserves its spline");
        auto flattened=stage->Flatten();
        if(op=="preview" && !(o.count("animated") && boolean(field(o,"animated")))) {
          // A disposable, static viewport sample of currently loaded content.
          // Work on the flattened copy; source/session opinions stay untouched.
          auto sampled=UsdStage::Open(flattened);
          double time=sampleTime(o);
          for(auto p:sampled->TraverseAll()) for(auto a:p.GetAttributes())
            if(a.GetNumTimeSamples() || a.HasSpline()) {
              VtValue value;
              if(!a.Get(&value,UsdTimeCode(time)) || !a.Clear() || !a.Set(value))
                throw std::runtime_error("Cannot sample preview attribute");
            }
          sampled->SetStartTimeCode(0);sampled->SetEndTimeCode(0);
        }
        if(!flattened->Export(temp.string())) throw std::runtime_error("Flatten failed");
      } else {
        auto layer=SdfLayer::CreateAnonymous("atlas-overrides.usda");
        // Collapse only owned overrides; retain the source composition below them.
        auto overrides=UsdUtilsFlattenLayerStack(UsdStage::Open(stage->GetSessionLayer(),UsdStage::LoadNone));
        if(!overrides)throw std::runtime_error("Cannot compose authoring layers for export");
        layer->TransferContent(overrides);
        // Stage metadata is read from the root/session, not inherited from sublayers.
        std::set<TfToken> fields;
        for(auto input:{stage->GetRootLayer(),stage->GetSessionLayer()})
          for(auto key:input->ListFields(SdfPath::AbsoluteRootPath())) fields.insert(key);
        for(auto key:fields) {
          VtValue v;
          if(key!=TfToken("subLayers") && key!=TfToken("subLayerOffsets") &&
             key!=TfToken("primChildren") && stage->GetMetadata(key,&v))
            layer->SetField(SdfPath::AbsoluteRootPath(),key,v);
        }
        // Absolute reference while packaging; relative reference for ordinary delivery.
        fs::path reference;
        if(!workingLayers.empty()) {
          if(!sourceConflicts().empty())throw std::runtime_error("Resolve source conflicts before delivery");
          sourceDirectory=target.parent_path()/(target.stem().string()+"-sources-"+newIdentity().substr(6));
          fs::create_directory(sourceDirectory);exportWorking(sourceDirectory,target.parent_path());
          reference=op=="package"?sourceDirectory/"source-0.usda":fs::relative(sourceDirectory/"source-0.usda",target.parent_path());
        } else reference=op=="package"?fs::path(source):fs::relative(source,target.parent_path());
        layer->SetSubLayerPaths({reference.string()});
        if(!layer->Export((op=="package"?overlay:temp).string())) throw std::runtime_error("Override export failed");
        if(op=="package") {
          dependencyBudget(overlay.string());
          if(!UsdUtilsCreateNewUsdzPackage(SdfAssetPath(overlay.string()),temp.string(),"scene.usda"))
            throw std::runtime_error("USDZ packaging failed");
        }
      }
      auto check=UsdStage::Open(temp.string());
      if(!check || !check->GetCompositionErrors().empty()) throw std::runtime_error("Export reopen failed");
      if(!errors.IsClean()) throw std::runtime_error("USD export reported errors");
      // No overwrite even if another writer created target while export was running.
      int fd=::open(temp.c_str(),O_RDONLY);
      if(fd<0) throw std::runtime_error("Cannot synchronize export");
      int synced=::fsync(fd); ::close(fd);
      if(synced!=0) throw std::runtime_error("Cannot synchronize export");
      fs::create_hard_link(temp,target); fs::remove(temp); fs::remove(overlay);
      fd=::open(target.parent_path().c_str(),O_RDONLY|O_DIRECTORY);
      if(fd>=0) { ::fsync(fd); ::close(fd); }
      return JsValue(Object{{"destination",JsValue(target.string())},{"kind",JsValue(op)},{"revision",JsValue(revision)}});
    } catch(...) { fs::remove(temp); fs::remove(overlay);if(!sourceDirectory.empty() && !fs::exists(target))fs::remove_all(sourceDirectory);throw; }
  }
public:
  JsValue request(const Object &o) {
    auto op=string(field(o,"op"));
    if(op=="open_workspace")return openWorkspace(o);
    if(op=="open") {
      auto file=fs::canonical(string(field(o,"source"))).string();
      size_t limit=100000;
      if(o.count("prim_limit")) { double n=number(field(o,"prim_limit"));
        if(n<1||n>100000||std::floor(n)!=n) throw std::runtime_error("prim_limit must be 1..100000"); limit=size_t(n); }
      TfErrorMark errors;
      auto candidate=UsdStage::Open(file,UsdStage::LoadNone);
      if(!candidate || !errors.IsClean() || !candidate->GetCompositionErrors().empty()) throw std::runtime_error("Cannot compose source stage");
      size_t count=0; for(auto p:candidate->TraverseAll()) if(++count>limit) throw std::runtime_error("Stage exceeds prim budget");
      candidate->SetEditTarget(candidate->GetSessionLayer());
      auto oldStage=stage;auto oldSource=source;auto oldLimit=primLimit;auto oldRevision=revision;
      auto oldLayers=authorLayers;auto oldTarget=targetName;authorLayers.clear();targetName="session";
      auto oldWorkspace=workspacePath,oldGeneration=workspaceGeneration,oldSaved=savedState,oldHash=openedSourceHash;auto oldDependencies=workspaceDependencies;
      auto oldWorking=workingLayers;auto oldWorkingDeps=workingDependencies;auto oldContext=targetContext;auto oldNode=targetNode;workingLayers.clear();workingDependencies.clear();targetContext.clear();targetNode=-1;
      workspacePath.clear();workspaceGeneration.clear();savedState.clear();workspaceDependencies.clear();
      stage=candidate;source=file;primLimit=limit;++revision;
      try {
        openedSourceHash=workspace::digest(workspace::read(file,workspace::fileLimit));
        auto object=snapshot(0).GetJsObject();undoHistory.clear();redoHistory.clear();
        object["undo_count"]=JsValue(0);object["redo_count"]=JsValue(0);return JsValue(object);
      } catch(...) {stage=oldStage;source=oldSource;primLimit=oldLimit;revision=oldRevision;authorLayers=oldLayers;targetName=oldTarget;
        workspacePath=oldWorkspace;workspaceGeneration=oldGeneration;savedState=oldSaved;openedSourceHash=oldHash;workspaceDependencies=oldDependencies;
        workingLayers=oldWorking;workingDependencies=oldWorkingDeps;targetContext=oldContext;targetNode=oldNode;throw;}
    }
    if(!stage) throw std::runtime_error("Open a stage first");
    if(op!="reload") valid();
    if(op=="snapshot") return snapshot(sampleTime(o));
    if(op=="curves") return curves(o);
    if(op=="source_targets")return sourceTargets(o);
    if(op=="identities")return identityRows();
    if(op=="spline")return splineInfo(o);
    if(op=="save_workspace")return saveWorkspace(o);
    if(op=="save"||op=="flatten"||op=="package"||op=="preview") return save(o,op);
    double time=sampleTime(o);
    if(o.count("time") && op!="attribute" && op!="transform" && op!="visibility" && op!="clear_sample" && op!="set_channel" && op!="move_key" && op!="copy_key" && op!="set_spline" && op!="set_interpolation" && op!="set_tangent" && op!="bake_curve" && op!="set_spline_value" && op!="move_spline_key" && op!="copy_spline_key" && op!="delete_spline_key")
      throw std::runtime_error("Time is accepted only for property, transform, visibility and curve-key edits");
    UsdTimeCode authoredTime=o.count("time")?UsdTimeCode(time):UsdTimeCode::Default();
    auto before=capture();
    TfErrorMark errors;
    try {
      if(op=="begin_source_editing") {
        beginWorking();
      } else if(op=="select_source_layer") {
        double node=o.count("node")?number(field(o,"node")):-1;
        if(node< -1 || node>1024 || std::floor(node)!=node)throw std::runtime_error("Invalid source mapping index");
        selectWorking(string(field(o,"name")),o.count("context")?string(field(o,"context")):"",int(node));
      } else if(op=="resolve_sources") {
        resolveSources(string(field(o,"action")));
      } else if(op=="undo" || op=="redo") {
        const auto &history=op=="undo"?undoHistory:redoHistory;
        if(history.empty())throw std::runtime_error("No "+op+" history");
        restore(history.back());
      } else if(op=="select_layer") {
        select(string(field(o,"name")));
      } else if(op=="create_layer") {
        auto name=string(field(o,"name"));
        if(name.empty() || name.size()>32 || name=="session" ||
          !std::all_of(name.begin(),name.end(),[](unsigned char c){return (c>='a'&&c<='z') || (c>='A'&&c<='Z') || (c>='0'&&c<='9') || c=='_' || c=='-';}))
          throw std::runtime_error("Layer name requires 1..32 ASCII letters, digits, underscores or hyphens; session is reserved");
        if(authorLayers.size()>=8)throw std::runtime_error("Maximum eight local authoring layers");
        for(const auto &a:authorLayers)if(a.name==name)throw std::runtime_error("Layer name already exists");
        auto layer=SdfLayer::CreateAnonymous(name+".usda");
        authorLayers.insert(authorLayers.begin(),{name,layer});
        std::vector<std::string> paths;for(const auto &a:authorLayers)paths.push_back(a.layer->GetIdentifier());
        stage->GetSessionLayer()->SetSubLayerPaths(paths);select(name);
      } else if(op=="repair_ids" || op=="reconcile_ids") {
        reconcileIdentities();
      } else if(op=="assign_ids") {
        if(targetName.rfind("working:",0)==0)throw std::runtime_error("Use repair_ids for per-occurrence identities while editing source copies");
        std::set<std::string> identities;
        for(auto p:stage->TraverseAll()) {
          if(p.IsAbstract() || !p.IsDefined())continue;
          auto value=p.GetCustomDataByKey(TfToken("atlas:uuid"));
          std::string identity;
          if(value.IsEmpty()) { identity=newIdentity(); p.SetCustomDataByKey(TfToken("atlas:uuid"),VtValue(identity)); }
          else if(value.IsHolding<std::string>()) identity=value.UncheckedGet<std::string>();
          else throw std::runtime_error("Invalid authored Atlas identity type");
          if(!validIdentity(identity) || !identities.insert(identity).second)
            throw std::runtime_error("Invalid or duplicate authored Atlas identity");
        }
      } else if(op=="timeline") {
        if(targetName!="session")throw std::runtime_error("Stage timeline metadata requires the session target");
        double start=number(field(o,"start")),end=number(field(o,"end")),rate=number(field(o,"time_codes_per_second"));
        if(std::abs(start)>1e9 || std::abs(end)>1e9 || end<start || rate<=0 || rate>1000)
          throw std::runtime_error("Timeline requires ordered times within +/-1e9 and rate in (0,1000]");
        stage->SetStartTimeCode(start);stage->SetEndTimeCode(end);stage->SetTimeCodesPerSecond(rate);
      } else if(op=="set_spline" || op=="set_interpolation" || op=="set_tangent" || op=="bake_curve" || op=="convert_frame_rate" || op=="set_spline_value" || op=="move_spline_key" || op=="copy_spline_key" || op=="delete_spline_key") {
        animate(o,op);
      } else if(op=="set_channel" || op=="move_key" || op=="copy_key") {
        editCurve(o,op);
      } else if(op=="clear_sample") {
        if(!o.count("time"))throw std::runtime_error("clear_sample requires a numeric time");
        auto a=prim(o).GetAttribute(TfToken(string(field(o,"name"))));
        if(!a || !target()->QueryTimeSample(stage->GetEditTarget().MapToSpecPath(a.GetPath()),targetTime(time)))
          throw std::runtime_error("No sample in the selected authoring layer at this time");
        if(!a.ClearAtTime(authoredTime))throw std::runtime_error("Cannot clear sample");
      } else if(op=="variant") {
        auto set=prim(o).GetVariantSet(string(field(o,"set")));
        auto choice=string(field(o,"value")); auto names=set.GetVariantNames();
        if(std::find(names.begin(),names.end(),choice)==names.end() || !set.SetVariantSelection(choice)) throw std::runtime_error("Unknown variant selection");
      } else if(op=="visibility") {
        auto p=prim(o); auto text=string(field(o,"value"));
        if(text!="inherited" && text!="invisible") throw std::runtime_error("Invalid visibility");
        if(!UsdGeomImageable(p))throw std::runtime_error("Expected imageable prim");
        auto a=p.CreateAttribute(TfToken("visibility"),SdfValueTypeNames->Token,false);
        if(o.count("time"))seedSamples(a);
        if(!a.Set(TfToken(text),authoredTime)) throw std::runtime_error("Visibility edit failed");
      } else if(op=="active") {
        if(!prim(o).SetActive(boolean(field(o,"value")))) throw std::runtime_error("Active edit failed");
      } else if(op=="transform") {
        auto p=prim(o); UsdGeomXformable x(p); const auto &v=field(o,"matrix");
        if(!x || !v.IsArray() || v.GetJsArray().size()!=16) throw std::runtime_error("Expected transformable prim and 16 matrix numbers");
        GfMatrix4d m; for(int i=0;i<16;++i) m[i/4][i%4]=number(v.GetJsArray()[i]);
        if(m[0][3]!=0||m[1][3]!=0||m[2][3]!=0||m[3][3]!=1||std::abs(m.GetDeterminant())<1e-12) throw std::runtime_error("Expected nonsingular affine row-major transform");
        auto attr=p.GetAttribute(TfToken("xformOp:transform:atlas"));
        auto transform=attr?UsdGeomXformOp(attr):x.AddTransformOp(UsdGeomXformOp::PrecisionDouble,TfToken("atlas"));
        if(!transform.Set(m,authoredTime) || !x.SetXformOpOrder({transform},x.GetResetXformStack())) throw std::runtime_error("Transform edit failed");
      } else if(op=="attribute") {
        auto a=prim(o).GetAttribute(TfToken(string(field(o,"name"))));
        if(!a || a.HasAuthoredConnections()) throw std::runtime_error("Expected existing unconnected attribute");
        if(o.count("time") && a.GetVariability()==SdfVariabilityUniform)throw std::runtime_error("Uniform attributes cannot have time samples");
        if(o.count("time") && (a.HasSpline() || target()->HasField(stage->GetEditTarget().MapToSpecPath(a.GetPath()),TfToken("spline"))))throw std::runtime_error("Spline requires explicit bake before time-sample editing");
        if(o.count("time"))seedSamples(a);
        auto type=a.GetTypeName(); const auto &v=field(o,"value"); bool ok=false;
        if(type==SdfValueTypeNames->Float) { auto n=number(v); if(std::abs(n)>std::numeric_limits<float>::max()) throw std::runtime_error("Float out of range"); ok=a.Set(float(n),authoredTime); }
        else if(type==SdfValueTypeNames->Double) ok=a.Set(number(v),authoredTime);
        else if(type==SdfValueTypeNames->Bool) ok=a.Set(boolean(v),authoredTime);
        else if(type==SdfValueTypeNames->Token) ok=a.Set(TfToken(string(v)),authoredTime);
        else if(type==SdfValueTypeNames->String) ok=a.Set(string(v),authoredTime);
        else {
          VtValue current;if(!a.Get(&current,authoredTime) || !numericValue(current))throw std::runtime_error("Attribute type is not editable by this profile");
          arrayLabels(a,current);
          ok=a.Set(numericInput(current,v),authoredTime);
        }
        if(!ok) throw std::runtime_error("Attribute edit failed");
      } else if(op=="load"||op=="unload") {
        auto p=prim(o,false); if(p.IsInstanceProxy() || !p.HasPayload()) throw std::runtime_error("Expected a concrete payload prim");
        if(op=="load") stage->Load(p.GetPath(),UsdLoadWithoutDescendants); else stage->Unload(p.GetPath());
      } else if(op=="reload") {
        if(!workingLayers.empty() && !sourceConflicts().empty())throw std::runtime_error("Source conflict: explicitly resolve_sources with keep_working or reload");
        // Session edits survive external layer reload; USD handles its composition caches.
        for(auto l:stage->GetUsedLayers()) if(!l->IsAnonymous()) l->Reload(true);
      } else if(op=="reset") {
        stage->GetSessionLayer()->Clear();authorLayers.clear();select("session");
      } else if(op=="clear_layer") {
        if(targetName.rfind("working:",0)==0)throw std::runtime_error("Clearing a source working copy is unsupported; edit its properties or resolve sources");
        target()->Clear();
        if(targetName=="session") {
          std::vector<std::string> paths;for(const auto &a:authorLayers)paths.push_back(a.layer->GetIdentifier());
          stage->GetSessionLayer()->SetSubLayerPaths(paths);
        }
      }
      else throw std::runtime_error("Unknown stage operation: "+op);
      valid(); if(!errors.IsClean()) throw std::runtime_error("USD edit reported errors");
      auto after=capture();
      auto result=snapshot(time);
      if(op=="undo") {remember(redoHistory,before);undoHistory.pop_back();}
      else if(op=="redo") {remember(undoHistory,before);redoHistory.pop_back();}
      else if(op=="reload") {undoHistory.clear();redoHistory.clear();}
      else if(before.session!=after.session || before.layers!=after.layers || before.target!=after.target || before.rules.GetRules()!=after.rules.GetRules() || before.workingTexts!=after.workingTexts || before.context!=after.context || before.node!=after.node || before.sourceHash!=after.sourceHash || before.workingDependencies!=after.workingDependencies) {remember(undoHistory,before);redoHistory.clear();}
      ++revision;auto object=result.GetJsObject();object["revision"]=JsValue(revision);
      if(op=="attribute" || op=="visibility" || op=="set_channel" || op=="move_key" || op=="copy_key") {
        auto a=prim(o).GetAttribute(TfToken(op=="visibility"?"visibility":string(field(o,"name"))));
        auto path=stage->GetEditTarget().MapToSpecPath(a.GetPath());VtValue expected,composed;
        bool authored=o.count("time")?target()->QueryTimeSample(path,targetTime(time),&expected):target()->HasField(path,TfToken("default"),&expected);
        if(authored && a.Get(&composed,authoredTime))object["edit_feedback"]=JsValue(expected==composed?"applied":"masked_by_stronger_layer");
        object["authored_spec_path"]=JsValue(path.GetString());if(o.count("time"))object["authored_layer_time"]=JsValue(targetTime(time));
      }
      object["undo_count"]=JsValue(int(undoHistory.size()));object["redo_count"]=JsValue(int(redoHistory.size()));return JsValue(object);
    } catch(...) {
      restore(before);throw;
    }
  }
};
int main() {
  Session session; std::string line;
  while(true) {
    line.clear(); bool oversized=false; char ch;
    while(std::cin.get(ch) && ch!='\n') {
      if(line.size()<1024*1024) line.push_back(ch); else oversized=true;
    }
    if(!std::cin && line.empty() && !oversized) break;
    TfErrorMark errors;
    try {
      if(oversized) throw std::runtime_error("Request exceeds 1 MiB");
      // Bound nesting before the JSON parser allocates recursive objects.
      int depth=0; bool quoted=false,escaped=false;
      for(char c:line) { if(quoted) { if(escaped) escaped=false; else if(c=='\\') escaped=true; else if(c=='"') quoted=false; }
        else if(c=='"') quoted=true; else if(c=='{'||c=='[') { if(++depth>32) throw std::runtime_error("Request nesting exceeds 32"); } else if(c=='}'||c==']') --depth; }
      JsParseError parse; auto request=JsParseString(line,&parse);
      if(!request.IsObject()) throw std::runtime_error("Invalid JSON request: "+parse.reason);
      auto result=session.request(request.GetJsObject());
      if(!errors.IsClean()) throw std::runtime_error("OpenUSD reported an error");
      emit(JsValue(Object{{"ok",JsValue(true)},{"result",result}}));
    } catch(const std::exception &e) {
      errors.Clear(); emit(JsValue(Object{{"ok",JsValue(false)},{"error",JsValue(e.what())}}));
    }
  }
}
