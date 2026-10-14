// Bounded static point-instancer expansion for the offline Atlas cook path.
#pragma once
#include <pxr/usd/usdGeom/pointInstancer.h>
#include <pxr/usd/usdGeom/xformable.h>
#include <pxr/usd/usd/references.h>
#include <pxr/base/js/json.h>
#include <set>
PXR_NAMESPACE_USING_DIRECTIVE
static JsArray atlasExpandPointInstancers(const UsdStageRefPtr &stage) {
  std::vector<UsdPrim> instancers;
  for(auto p:stage->Traverse()) if(p.GetTypeName()==TfToken("PointInstancer"))instancers.push_back(p);
  JsArray report;size_t instances=0,expandedPrims=0,expandedVertices=0,expandedIndices=0;
  for(auto p:instancers) {
    UsdGeomPointInstancer source(p);auto at=UsdTimeCode(stage->GetStartTimeCode());
    for(auto a:p.GetAttributes()) if(a.ValueMightBeTimeVarying())throw std::runtime_error("Animated point-instancer placements require baking: "+p.GetPath().GetString());
    for(const auto &name:{"velocities","accelerations","angularVelocities"})if(p.GetAttribute(TfToken(name)).HasAuthoredValueOpinion())throw std::runtime_error("Point-instancer motion derivatives require baking");
    SdfPathVector prototypes;source.GetPrototypesRel().GetTargets(&prototypes);
    if(prototypes.empty() || prototypes.size()>256)throw std::runtime_error("Point-instancer prototype count outside 1..256");
    std::vector<size_t> counts,vertices,indicesPerPrototype;
    for(auto path:prototypes) {
      if(path==p.GetPath() || !path.HasPrefix(p.GetPath()))throw std::runtime_error("Point-instancer prototypes must be descendants of their instancer");
      auto prototype=stage->GetPrimAtPath(path);
      if(!prototype || !prototype.IsActive() || prototype.IsInstance())throw std::runtime_error("Invalid point-instancer prototype");
      size_t count=0,vertexCount=0,indexCount=0;
      for(auto child:UsdPrimRange(prototype)) {
        auto type=child.GetTypeName().GetString();
        if(type!="Xform" && type!="Scope" && type!="Mesh" && type!="Material" && type!="Shader" && type!="GeomSubset")throw std::runtime_error("Unsupported point-instancer prototype type: "+type);
        for(auto a:child.GetAttributes())if(a.ValueMightBeTimeVarying())throw std::runtime_error("Animated point-instancer prototype requires baking");
        if(type=="Mesh") {
          UsdGeomMesh mesh(child);VtVec3fArray points;VtIntArray faces;
          mesh.GetPointsAttr().Get(&points,at);mesh.GetFaceVertexCountsAttr().Get(&faces,at);vertexCount+=points.size();
          for(auto n:faces){if(n<3)throw std::runtime_error("Invalid point-prototype face");indexCount+=size_t(n-2)*3;}
        }
        if(child.IsInstance())throw std::runtime_error("Nested native instances in point prototypes require baking");
        if(++count>10000)throw std::runtime_error("Point prototype exceeds prim budget");
      }
      counts.push_back(count);vertices.push_back(vertexCount);indicesPerPrototype.push_back(indexCount);
    }
    VtIntArray indices;source.GetProtoIndicesAttr().Get(&indices,at);
    instances+=indices.size();if(instances>4096)throw std::runtime_error("Point-instancer expansion exceeds 4096 occurrences");
    VtInt64Array ids;source.GetIdsAttr().Get(&ids,at);
    if(!ids.empty() && ids.size()!=indices.size())throw std::runtime_error("Point-instancer ID count mismatch");
    std::set<int64_t> unique;
    for(size_t i=0;i<indices.size();++i) {
      if(indices[i]<0 || size_t(indices[i])>=prototypes.size())throw std::runtime_error("Point-instancer prototype index out of range");
      expandedVertices+=vertices[indices[i]];expandedIndices+=indicesPerPrototype[indices[i]];
      if(expandedVertices>1000000 || expandedIndices>3000000)throw std::runtime_error("Point expansion exceeds geometry memory budget");
      expandedPrims+=counts[indices[i]];if(expandedPrims>100000)throw std::runtime_error("Expanded point instances exceed prim budget");
      if(!unique.insert(ids.empty()?int64_t(i):ids[i]).second)throw std::runtime_error("Duplicate point-instancer identity");
    }
    VtMatrix4dArray matrices;
    if(!source.ComputeInstanceTransformsAtTime(&matrices,at,at,UsdGeomPointInstancer::IncludeProtoXform,UsdGeomPointInstancer::IgnoreMask) || matrices.size()!=indices.size())throw std::runtime_error("Cannot compute point-instance transforms");
    auto mask=source.ComputeMaskAtTime(at);
    if(!mask.empty() && mask.size()!=indices.size())throw std::runtime_error("Point-instancer visibility mask count mismatch");
    std::string identity=p.GetPath().GetString();auto custom=p.GetCustomDataByKey(TfToken("atlas:uuid"));
    if(custom.IsHolding<std::string>())identity=custom.UncheckedGet<std::string>();
    std::vector<SdfPath> created;size_t shown=0;
    for(size_t i=0;i<indices.size();++i) {
      if(!mask.empty() && !mask[i])continue;
      auto id=std::to_string(ids.empty()?int64_t(i):ids[i]);auto name=id;if(name[0]=='-')name[0]='n';
      auto path=p.GetPath().AppendChild(TfToken("AtlasPoint_"+name));
      if(stage->GetPrimAtPath(path))throw std::runtime_error("Point expansion collides with an existing prim");
      auto child=stage->DefinePrim(path,stage->GetPrimAtPath(prototypes[indices[i]]).GetTypeName());
      if(!child.GetReferences().AddInternalReference(prototypes[indices[i]]))throw std::runtime_error("Cannot reference point prototype");
      for(int r=0;r<4;++r)for(int c=0;c<4;++c)if(!std::isfinite(matrices[i][r][c]))throw std::runtime_error("Non-finite point transform");
      if(std::abs(matrices[i].GetDeterminant())<1e-12)throw std::runtime_error("Singular point transform");
      auto x=UsdGeomXformable(child);auto op=x.MakeMatrixXform();
      if(!op || !op.Set(matrices[i]))throw std::runtime_error("Cannot author point occurrence transform");
      for(auto occurrence:UsdPrimRange(child)) {
        auto suffix=occurrence.GetPath().GetString().substr(path.GetString().size());
        auto stable=identity+"/point/"+id+suffix;
        if(stable.size()>128)throw std::runtime_error("Point occurrence identity exceeds 128 bytes; assign a shorter instancer atlas:uuid");
        occurrence.SetCustomDataByKey(TfToken("atlas:uuid"),VtValue(stable));
      }
      created.push_back(path);++shown;
    }
    // Abstract source prototypes remain valid reference targets without being
    // imported as extra, visible geometry by Blender.
    for(auto path:prototypes)if(!stage->GetPrimAtPath(path).SetSpecifier(SdfSpecifierClass))throw std::runtime_error("Cannot abstract point prototype");
    if(!p.SetTypeName(TfToken("Xform")))throw std::runtime_error("Cannot replace temporary point-instancer type");
    report.emplace_back(JsObject{{"path",JsValue(p.GetPath().GetString())},{"occurrences",JsValue(int(indices.size()))},
      {"visible_occurrences",JsValue(int(shown))},{"prototypes",JsValue(int(prototypes.size()))},
      {"policy",JsValue("Static placement expansion; source unchanged, runtime prototype residency not retained")}});
  }
  return report;
}
