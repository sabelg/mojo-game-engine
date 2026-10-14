// Deterministic finite tube tessellation for static, round, constant-width curves.
#pragma once
#include <pxr/usd/usdGeom/basisCurves.h>
#include <pxr/usd/usdGeom/mesh.h>
#include <pxr/usd/usdGeom/primvarsAPI.h>
#include <pxr/base/js/json.h>
#include <cmath>
PXR_NAMESPACE_USING_DIRECTIVE
static JsArray atlasBakeCurves(const UsdStageRefPtr &stage) {
  std::vector<UsdPrim> curves;JsArray report;size_t totalVertices=0,totalIndices=0;
  for(auto p:stage->Traverse())if(p.GetTypeName()==TfToken("BasisCurves"))curves.push_back(p);
  for(auto p:curves) {
    UsdGeomBasisCurves curve(p);auto at=UsdTimeCode(stage->GetStartTimeCode());
    for(auto a:p.GetAttributes())if(a.ValueMightBeTimeVarying())throw std::runtime_error("Animated curves require geometry-cache baking");
    for(auto relation:p.GetRelationships())if(relation.GetName().GetString().find("skel:")==0 && relation.HasAuthoredTargets())throw std::runtime_error("Skinned curves require mesh baking");
    if(curve.GetNormalsAttr().HasAuthoredValueOpinion())throw std::runtime_error("Oriented ribbon curves are outside the round-tube profile");
    for(auto pv:UsdGeomPrimvarsAPI(p).GetPrimvars())if(pv.HasAuthoredValue() && pv.GetInterpolation()!=UsdGeomTokens->constant)throw std::runtime_error("Nonconstant curve primvars require material baking");
    TfToken type,basis,wrap;curve.GetTypeAttr().Get(&type,at);curve.GetBasisAttr().Get(&basis,at);curve.GetWrapAttr().Get(&wrap,at);
    if(wrap!=UsdGeomTokens->nonperiodic || (type!=UsdGeomTokens->linear && !(type==UsdGeomTokens->cubic && basis==UsdGeomTokens->bezier)))throw std::runtime_error("Curve profile supports nonperiodic linear or cubic Bezier curves");
    VtVec3fArray source;VtIntArray counts;VtFloatArray widths;
    curve.GetPointsAttr().Get(&source,at);curve.GetCurveVertexCountsAttr().Get(&counts,at);curve.GetWidthsAttr().Get(&widths,at);
    auto interpolation=curve.GetWidthsInterpolation();
    if(!((interpolation==UsdGeomTokens->constant && widths.size()==1) || (interpolation==UsdGeomTokens->uniform && widths.size()==counts.size())))throw std::runtime_error("Curve profile needs constant or per-curve uniform widths");
    if(source.size()>100000 || counts.empty() || counts.size()>4096)throw std::runtime_error("Curve source exceeds geometry budget");
    for(auto v:source)for(int i=0;i<3;++i)if(!std::isfinite(v[i]))throw std::runtime_error("Non-finite curve point");
    for(auto w:widths)if(!std::isfinite(w)||w<=0)throw std::runtime_error("Curve widths must be finite and positive");
    int sides=8,steps=8;
    p.GetAttribute(TfToken("userProperties:atlas_curve_sides")).Get(&sides);
    p.GetAttribute(TfToken("userProperties:atlas_curve_steps")).Get(&steps);
    if(sides<3||sides>32||steps<1||steps>64)throw std::runtime_error("Curve tessellation requires sides 3..32 and steps 1..64");
    size_t expected=0,predictedVertices=0,predictedIndices=0;
    for(auto count:counts) {
      if(count<2 || (type==UsdGeomTokens->cubic && (count<4 || (count-1)%3)))throw std::runtime_error("Invalid curve control-point count");
      expected+=size_t(count);size_t samples=type==UsdGeomTokens->linear?size_t(count):size_t((count-1)/3)*steps+1;
      predictedVertices+=samples*(sides+1)+2*(sides+2);predictedIndices+=(samples-1)*sides*6+2*sides*3;
    }
    if(expected!=source.size() || predictedVertices>250000 || predictedIndices>750000 || totalVertices+predictedVertices>1000000 || totalIndices+predictedIndices>3000000)throw std::runtime_error("Curve tessellation exceeds bounded geometry profile");
    totalVertices+=predictedVertices;totalIndices+=predictedIndices;
    VtVec3fArray points,normals;VtVec2fArray uv;VtIntArray faces,indices;
    auto vertex=[&](GfVec3d point,GfVec3d normal,GfVec2f st){for(int axis=0;axis<3;++axis)if(!std::isfinite(float(point[axis])))throw std::runtime_error("Tessellated curve point exceeds float range");int index=int(points.size());points.push_back(GfVec3f(point));normals.push_back(GfVec3f(normal));uv.push_back(st);return index;};
    auto triangle=[&](int a,int b,int c){faces.push_back(3);indices.push_back(a);indices.push_back(b);indices.push_back(c);};
    size_t offset=0;
    for(size_t ci=0;ci<counts.size();++ci) {
      int count=counts[ci];std::vector<GfVec3d> samples;
      if(type==UsdGeomTokens->linear)for(int i=0;i<count;++i)samples.emplace_back(source[offset+i]);
      else for(int segment=0;segment<(count-1)/3;++segment) {
        GfVec3d a(source[offset+segment*3]),b(source[offset+segment*3+1]),c(source[offset+segment*3+2]),d(source[offset+segment*3+3]);
        for(int i=0;i<=steps;++i) {
          if(segment && i==0)continue;
          double t=double(i)/steps,u=1-t;samples.push_back(a*(u*u*u)+b*(3*u*u*t)+c*(3*u*t*t)+d*(t*t*t));
        }
      }
      for(size_t i=1;i<samples.size();++i)if((samples[i]-samples[i-1]).GetLength()<1e-10)throw std::runtime_error("Curve contains coincident adjacent samples");
      offset+=count;double radius=widths[interpolation==UsdGeomTokens->constant?0:ci]*.5;
      std::vector<GfVec3d> tangents,radials;
      GfVec3d radial(0);size_t base=points.size();
      for(size_t i=0;i<samples.size();++i) {
        auto tangent=samples[i==samples.size()-1?i:i+1]-samples[i==0?i:i-1];
        if(tangent.GetLength()<1e-10)throw std::runtime_error("Curve has a degenerate tangent or reversing cusp");
        tangent.Normalize();radial-=tangent*GfDot(radial,tangent);
        if(radial.GetLength()<1e-8)radial=GfCross(tangent,std::abs(tangent[0])<.8?GfVec3d(1,0,0):GfVec3d(0,1,0));
        radial.Normalize();auto binormal=GfCross(tangent,radial);tangents.push_back(tangent);radials.push_back(radial);
        for(int j=0;j<=sides;++j) {
          double angle=double(j)*6.283185307179586/sides;auto normal=radial*std::cos(angle)+binormal*std::sin(angle);
          vertex(samples[i]+normal*radius,normal,GfVec2f(float(j)/sides,float(i)/(samples.size()-1)));
        }
        if(i)for(int j=0;j<sides;++j){int a=int(base+(i-1)*(sides+1)+j),b=a+sides+1;triangle(a,a+1,b);triangle(a+1,b+1,b);}
      }
      for(int end=0;end<2;++end) {
        size_t i=end?samples.size()-1:0;auto normal=tangents[i]*(end?1.0:-1.0);auto radial=radials[i];auto binormal=GfCross(tangents[i],radial);
        int center=vertex(samples[i],normal,GfVec2f(.5));int ring=int(points.size());
        for(int j=0;j<=sides;++j){double angle=j*6.283185307179586/sides;vertex(samples[i]+(radial*std::cos(angle)+binormal*std::sin(angle))*radius,normal,GfVec2f(float(.5+.5*std::cos(angle)),float(.5+.5*std::sin(angle))));}
        for(int j=0;j<sides;++j)if(end)triangle(center,ring+j,ring+j+1);else triangle(center,ring+j+1,ring+j);
      }
    }
    if(!p.SetTypeName(TfToken("Mesh")))throw std::runtime_error("Cannot convert temporary curve to mesh");
    UsdGeomMesh mesh(p);mesh.CreateSubdivisionSchemeAttr().Set(UsdGeomTokens->none);mesh.CreatePointsAttr().Set(points);mesh.CreateNormalsAttr().Set(normals);mesh.SetNormalsInterpolation(UsdGeomTokens->vertex);mesh.CreateFaceVertexCountsAttr().Set(faces);mesh.CreateFaceVertexIndicesAttr().Set(indices);
    UsdGeomPrimvarsAPI(p).CreatePrimvar(TfToken("st"),SdfValueTypeNames->TexCoord2fArray,UsdGeomTokens->vertex).Set(uv);
    GfVec3f minimum=points[0],maximum=points[0];for(auto point:points)for(int i=0;i<3;++i){minimum[i]=std::min(minimum[i],point[i]);maximum[i]=std::max(maximum[i],point[i]);}
    mesh.CreateExtentAttr().Set(VtVec3fArray{minimum,maximum});
    report.emplace_back(JsObject{{"path",JsValue(p.GetPath().GetString())},{"vertices",JsValue(int(points.size()))},{"triangles",JsValue(int(faces.size()))},
      {"sides",JsValue(sides)},{"steps",JsValue(steps)},{"policy",JsValue("Static capped round-tube tessellation; nonperiodic linear/Bezier, constant/per-curve widths")}});
  }
  return report;
}
