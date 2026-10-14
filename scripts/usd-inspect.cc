// OpenUSD stage/dependency inspection for Atlas's offline authoring bridge.
#include <pxr/pxr.h>
#include <pxr/base/js/json.h>
#include <pxr/base/tf/errorMark.h>
#include <pxr/usd/usd/stage.h>
#include <pxr/usd/usd/primRange.h>
#include <pxr/usd/usdGeom/metrics.h>
#include <pxr/usd/usdGeom/mesh.h>
#include <pxr/usd/usdShade/shader.h>
#include <pxr/usd/usdUtils/dependencies.h>
#include <iostream>
#include "usd-camera.h"
#include "usd-materials.h"
#include "usd-lights.h"
#include "usd-instancers.h"
#include "usd-curves.h"
#include <set>
#include "usd-animation-sampling.h"
PXR_NAMESPACE_USING_DIRECTIVE
int main(int argc, char **argv) {
  if (argc != 2 && argc != 3) { std::cerr << "Usage: atlas-usd-inspect scene.usd [composed.usdc]\n"; return 2; }
  try {
    TfErrorMark errors;
    std::vector<SdfLayerRefPtr> layers;
    std::vector<std::string> assets, unresolved;
    if (!UsdUtilsComputeAllDependencies(SdfAssetPath(argv[1]), &layers, &assets, &unresolved))
      throw std::runtime_error("Cannot enumerate USD dependencies");
    auto stage = UsdStage::Open(argv[1]);
    if (!stage) throw std::runtime_error("Cannot open USD stage");
    if (!errors.IsClean() || !stage->GetCompositionErrors().empty())
      throw std::runtime_error("Unresolved or invalid USD composition");
    stage->SetEditTarget(stage->GetSessionLayer());
    auto curveBakes=atlasBakeCurves(stage);
    auto pointInstances=atlasExpandPointInstancers(stage);
    if(argc==3) {
      // Expand native instances only in the temporary conversion stage. This
      // permits each occurrence to receive its full composed-path identity.
      for(int depth=0;depth<64;++depth) {
        std::vector<UsdPrim> instances;
        for(const auto &p:stage->Traverse()) if(p.IsInstance()) instances.push_back(p);
        if(instances.empty()) break;
        if(depth==63) throw std::runtime_error("Nested instance depth exceeds 64");
        for(auto p:instances) if(!p.SetInstanceable(false)) throw std::runtime_error("Cannot expand instance for cooking");
      }
    }
    JsArray dependencies, missing, prims, unsupported, cameras, translations, geometry_bakes, lights, camera_tracks, light_tracks, local_lights, visibility_tracks;
    std::set<SdfPath> translatedShaders;
    std::set<std::string> paths;
    for (const auto &layer : layers) paths.insert(layer->GetRealPath());
    for (const auto &asset : assets) paths.insert(asset);
    for (const auto &path : paths) dependencies.emplace_back(path);
    for (const auto &path : unresolved) missing.emplace_back(path);
    const std::set<std::string> types = {"", "Xform", "Scope", "Mesh", "Material", "Shader",
      "NodeGraph", "GeomSubset", "SkelRoot", "Skeleton", "SkelAnimation", "Camera", "DistantLight",
      "DomeLight", "SphereLight", "RectLight", "DiskLight", "CylinderLight", "BlendShape"};
    const std::set<std::string> shaders = {"UsdPreviewSurface", "UsdUVTexture",
      "UsdPrimvarReader_float2", "UsdTransform2d"};
    int mesh_count = 0, skeletons = 0;
    bool animated = false;
    size_t cameraSamples=0,lightSamples=0,visibilitySamples=0;
    double start=stage->GetStartTimeCode(),end=stage->GetEndTimeCode(),rate=stage->GetTimeCodesPerSecond();
    if(!std::isfinite(start)||!std::isfinite(end)||!std::isfinite(rate)||end<start||end-start>10000||rate<=0)
      throw std::runtime_error("Invalid USD animation interval");
    for (const auto &prim : UsdPrimRange::Stage(stage, UsdTraverseInstanceProxies())) {
      const auto type = prim.GetTypeName().GetString();
      const auto path = prim.GetPath().GetString();
      if (prims.size() >= 100000) throw std::runtime_error("Stage exceeds 100000 prims");
      prims.emplace_back(JsObject{{"path", JsValue(path)}, {"type", JsValue(type)}});
      std::string stable=path;
      auto authoredIdentity=prim.GetCustomDataByKey(TfToken("atlas:uuid"));
      if(authoredIdentity.IsHolding<std::string>()) {
        stable=authoredIdentity.UncheckedGet<std::string>();
        if(stable.empty()||stable.size()>128) throw std::runtime_error("Invalid authored Atlas identity");
      }
      if (argc == 3 && !prim.IsInstanceProxy())
        prim.CreateAttribute(TfToken("userProperties:atlas_id"), SdfValueTypeNames->String, true).Set(stable);
      if (!types.count(type)) unsupported.emplace_back(path + ": unsupported type " + type);
      for (const auto &attribute : prim.GetAttributes()) {
        if (attribute.GetNumTimeSamples() > 10001)
          unsupported.emplace_back(path + ": too many time samples");
        if (attribute.ValueMightBeTimeVarying()) {
          animated = true;
          if (type == "Shader" || type == "Material")
            unsupported.emplace_back(path + ": animated shading requires baking");
        }
      }
      if (type == "DistantLight" || type == "DomeLight") {
        auto light=atlasLight(prim,start);
        if(!light.IsNull()) {
          lights.push_back(light); bool varying=false;
          for(auto ancestor=prim;ancestor && !ancestor.IsPseudoRoot();ancestor=ancestor.GetParent())
            for(auto a:ancestor.GetAttributes()) if(a.ValueMightBeTimeVarying()) varying=true;
          if(varying) {
            JsArray samples;
            for(double t:atlasAncestorSampleTimes(prim,start,end)) {
              if(++lightSamples>16384) throw std::runtime_error("Light animation exceeds 16384 total samples");
              auto next=atlasLight(prim,t);
              if(next.IsNull()) throw std::runtime_error("Animated light leaves the supported runtime profile");
              auto sample=next.GetJsObject(); sample["seconds"]=JsValue((t-start)/rate);
              samples.emplace_back(sample);
            }
            light_tracks.emplace_back(JsObject{{"id",JsValue(path)},{"samples",JsValue(samples)}});
          }
        }
      }
      if (type == "Camera") {
        cameras.emplace_back(atlasCamera(prim,start));
        bool varying=false;
        for(auto ancestor=prim;ancestor && !ancestor.IsPseudoRoot();ancestor=ancestor.GetParent())
          for(auto a:ancestor.GetAttributes()) if(a.ValueMightBeTimeVarying()) varying=true;
        if(varying) {
          JsArray samples;
          for(double t:atlasAncestorSampleTimes(prim,start,end)) {
            if(++cameraSamples>16384) throw std::runtime_error("Camera animation exceeds 16384 total samples");
            auto sample=atlasCamera(prim,t).GetJsObject();
            const auto &values=sample.at("world").GetJsArray();
            GfMatrix4d m; for(int i=0;i<16;++i)m[i/4][i%4]=values[i].GetReal();
            for(int r=0;r<3;++r) for(int c=0;c<3;++c) {
              double dot=0; for(int k=0;k<3;++k)dot+=m[r][k]*m[c][k];
              if(std::abs(dot-(r==c?1:0))>1e-5) throw std::runtime_error("Animated cameras require rigid transforms");
            }
            if(m.GetDeterminant()<0) throw std::runtime_error("Animated camera reflection is unsupported");
            auto q=m.ExtractRotationQuat().GetNormalized(); auto v=q.GetImaginary();
            sample["rotation"]=JsValue(JsArray{JsValue(v[0]),JsValue(v[1]),JsValue(v[2]),JsValue(q.GetReal())});
            sample["seconds"]=JsValue((t-start)/rate);
            samples.emplace_back(sample);
          }
          camera_tracks.emplace_back(JsObject{{"id",JsValue(path)},{"samples",JsValue(samples)}});
        }
      }
      if(type=="SphereLight") { auto light=atlasPointLight(prim,start); if(!light.IsNull())local_lights.push_back(light); }
      if (type == "Skeleton") ++skeletons;
      if(type=="BlendShape") {
        for(auto a:prim.GetAttributes()) {
          if(a.GetName().GetString().find("inbetweens:")==0 || a.ValueMightBeTimeVarying())
            unsupported.emplace_back(path+": in-between or time-varying blend-shape deltas require baking");
        }
      }
      if (type == "Mesh") {
        ++mesh_count;
        std::set<double> visibilityTimes{start,end};
        bool authoredVisibility=false;
        for(auto ancestor=prim;ancestor && !ancestor.IsPseudoRoot();ancestor=ancestor.GetParent()) {
          auto a=ancestor.GetAttribute(TfToken("visibility"));
          if(a && a.HasAuthoredValueOpinion()) {
            authoredVisibility=true; std::vector<double> times;a.GetTimeSamples(&times);
            for(double t:times) if(t>=start && t<=end)visibilityTimes.insert(t);
          }
        }
        if(authoredVisibility) {
          visibilitySamples+=visibilityTimes.size();
          if(visibilitySamples>100000 || visibilityTimes.size()>10001 || visibility_tracks.size()>=4096)throw std::runtime_error("Visibility track budget exceeded");
          JsArray samples;
          for(double t:visibilityTimes) samples.emplace_back(JsObject{{"seconds",JsValue((t-start)/rate)},
            {"visible",JsValue(UsdGeomImageable(prim).ComputeVisibility(UsdTimeCode(t))!=UsdGeomTokens->invisible)}});
          visibility_tracks.emplace_back(JsObject{{"id",JsValue(stable)},{"samples",JsValue(samples)}});
          if(argc==3)prim.CreateAttribute(TfToken("userProperties:atlas_visibility"),SdfValueTypeNames->String,true).Set(stable);
        }
        UsdGeomMesh mesh(prim);
        if (mesh.GetPointsAttr().ValueMightBeTimeVarying() ||
            mesh.GetFaceVertexCountsAttr().ValueMightBeTimeVarying() ||
            mesh.GetFaceVertexIndicesAttr().ValueMightBeTimeVarying())
          unsupported.emplace_back(path + ": time-varying mesh geometry requires baking to a supported representation");
        TfToken subdivision;
        mesh.GetSubdivisionSchemeAttr().Get(&subdivision);
        if (subdivision != UsdGeomTokens->none) {
          int level=0;
          auto attribute=prim.GetAttribute(TfToken("userProperties:atlas_subdivision_level"));
          if(attribute) attribute.Get(&level);
          VtVec3fArray points; mesh.GetPointsAttr().Get(&points);
          VtIntArray faces; mesh.GetFaceVertexCountsAttr().Get(&faces);
          size_t corners=0; for(auto n:faces) { if(n<0) throw std::runtime_error("Invalid subdivision face count"); corners+=size_t(n); }
          if((subdivision!=UsdGeomTokens->catmullClark && subdivision!=UsdGeomTokens->bilinear) || level<1 || level>3)
            unsupported.emplace_back(path + ": subdivision needs explicit userProperties:atlas_subdivision_level (1..3), or bake it to subdivisionScheme=none");
          else if(points.size()>250000 || corners*(size_t(1)<<(2*level))>750000)
            unsupported.emplace_back(path + ": subdivision bake exceeds conservative geometry budget");
          else geometry_bakes.emplace_back(JsObject{{"path",JsValue(path)},{"identity",JsValue(stable)},{"kind",JsValue("subdivision")},{"level",JsValue(level)}});
        }
      }
      if (type == "Shader") {
        TfToken id;
        UsdShadeShader shader(prim);
        shader.GetIdAttr().Get(&id);
        if (atlasMaterial(shader,id,argc==3,unsupported)) {
          translatedShaders.insert(prim.GetPath());
          translations.emplace_back(JsObject{{"path",JsValue(path)},{"source",JsValue(id.GetString())},{"target",JsValue("UsdPreviewSurface constant metallic/roughness approximation")}});
        } else if (!shaders.count(id.GetString())) unsupported.emplace_back(path + ": unsupported shader " + id.GetString());
        if (id == TfToken("UsdPreviewSurface")) {
          for (const auto *name : {"displacement", "clearcoat", "useSpecularWorkflow"}) {
            auto input = shader.GetInput(TfToken(name));
            VtValue value;
            if (input && (input.HasConnectedSource() || (input.GetAttr().Get(&value) &&
                ((value.IsHolding<float>() && value.UncheckedGet<float>() != 0) ||
                 (value.IsHolding<int>() && value.UncheckedGet<int>() != 0)))))
              unsupported.emplace_back(path + ": bake unsupported Preview Surface input " + name);
          }
        }
        if (id == TfToken("UsdUVTexture")) {
          SdfAssetPath texture;
          shader.GetInput(TfToken("file")).Get(&texture);
          if (texture.GetAssetPath().find("<UDIM>") != std::string::npos)
            unsupported.emplace_back(path + ": bake UDIM textures into supported texture assets");
        }
      }

    }
    if(argc==3 && unsupported.empty()) {
      for(const auto &prim:stage->Traverse()) if(prim.GetTypeName()==TfToken("Material")) {
        SdfPath selected;
        for(const auto &name:{"outputs:surface","outputs:mtlx:surface"}) {
          auto attr=prim.GetAttribute(TfToken(name)); SdfPathVector paths;
          if(attr) attr.GetConnections(&paths);
          if(paths.size()==1 && translatedShaders.count(paths[0].GetPrimPath())) {
            if(!selected.IsEmpty() && selected!=paths[0].GetPrimPath())
              throw std::runtime_error("Ambiguous universal/MaterialX surface binding");
            selected=paths[0].GetPrimPath();
          }
        }
        if(!selected.IsEmpty()) {
          auto universal=prim.GetAttribute(TfToken("outputs:surface")); SdfPathVector existing;
          if(universal) universal.GetConnections(&existing);
          if(!existing.empty() && existing[0].GetPrimPath()!=selected)
            throw std::runtime_error("Conflicting universal and MaterialX surface binding");
          prim.CreateAttribute(TfToken("outputs:surface"),SdfValueTypeNames->Token,false)
            .SetConnections({selected.AppendProperty(TfToken("outputs:surface"))});
        }
      }
    }
    if(argc==3 && unsupported.empty() && !visibility_tracks.empty()) {
      // Geometry must survive conversion even when hidden at the start time.
      // The runtime companion restores composed visibility independently.
      for(const auto &prim:stage->Traverse()) {
        auto imageable=UsdGeomImageable(prim);
        if(imageable)imageable.CreateVisibilityAttr().Set(UsdGeomTokens->inherited);
      }
    }
    int conversionFactor=animated?atlasConversionGridFactor(stage):1;
    JsObject report{{"openusd_version", JsValue(PXR_VERSION)}, {"point_instancers",JsValue(pointInstances)}, {"curve_bakes",JsValue(curveBakes)},
      {"conversion_grid_factor",JsValue(conversionFactor)},{"conversion_time_codes_per_second",JsValue(rate*conversionFactor)},
      {"conversion_start",JsValue(start*conversionFactor)},{"conversion_end",JsValue(end*conversionFactor)},
      {"dependencies", JsValue(dependencies)}, {"unresolved", JsValue(missing)},
      {"visibility_tracks",JsValue(visibility_tracks)}, {"local_lights",JsValue(local_lights)}, {"light_tracks",JsValue(light_tracks)}, {"camera_tracks",JsValue(camera_tracks)}, {"lights",JsValue(lights)}, {"geometry_bakes",JsValue(geometry_bakes)}, {"material_translations",JsValue(translations)}, {"cameras", JsValue(cameras)}, {"prims", JsValue(prims)}, {"unsupported", JsValue(unsupported)},
      {"meshes", JsValue(mesh_count)}, {"skeletons", JsValue(skeletons)},
      {"animated", JsValue(animated)},
      {"up_axis", JsValue(UsdGeomGetStageUpAxis(stage).GetString())},
      {"meters_per_unit", JsValue(UsdGeomGetStageMetersPerUnit(stage))},
      {"start", JsValue(stage->GetStartTimeCode())}, {"end", JsValue(stage->GetEndTimeCode())},
      {"time_codes_per_second", JsValue(stage->GetTimeCodesPerSecond())}};
    if (!errors.IsClean()) throw std::runtime_error("USD inspection or identity annotation failed");
    if (argc == 3 && !unsupported.empty()) throw std::runtime_error("Unsupported USD conversion features");
    if (argc == 3 && !(animated?atlasBakeConversionStage(stage,conversionFactor):stage->Flatten())->Export(argv[2]))
      throw std::runtime_error("Cannot write composed USD stage");
    std::cout << JsWriteToString(JsValue(report)) << '\n';
    return 0;
  } catch (const std::exception &error) { std::cerr << error.what() << '\n'; return 1; }
}
