// Small runtime profile: one distant light plus untextured dome lighting.
#pragma once
#include <pxr/usd/usdLux/lightAPI.h>
#include <pxr/usd/usdLux/blackbody.h>
#include <pxr/usd/usdGeom/xformable.h>
#include <pxr/usd/usdGeom/imageable.h>
#include <pxr/usd/usdGeom/metrics.h>
#include <pxr/base/js/json.h>
#include <cmath>
PXR_NAMESPACE_USING_DIRECTIVE
static JsValue atlasLight(const UsdPrim &prim,double time) {
  const auto type=prim.GetTypeName().GetString();
  if(type!="DistantLight" && type!="DomeLight") return JsValue();
  UsdLuxLightAPI api(prim); UsdTimeCode at(time);
  if(UsdGeomImageable(prim).ComputeVisibility(at)==UsdGeomTokens->invisible) return JsValue();
  // Graphs, textures, collections and independent diffuse/specular gains need
  // renderer features outside this explicit profile. Keep them authoring-only.
  for(auto a:prim.GetAttributes()) if(a.HasAuthoredConnections()) return JsValue();
  for(auto r:prim.GetRelationships()) if(r.HasAuthoredTargets()) return JsValue();
  float diffuse=1,specular=1; api.GetDiffuseAttr().Get(&diffuse,at);api.GetSpecularAttr().Get(&specular,at);
  if(diffuse!=1||specular!=1) return JsValue();
  if(type=="DomeLight") {
    SdfAssetPath texture; auto a=prim.GetAttribute(TfToken("inputs:texture:file"));
    if(a && a.Get(&texture,at) && !texture.GetAssetPath().empty()) return JsValue();
  }
  float intensity=1,exposure=0,temperature=6500; bool kelvin=false,normalize=false;
  GfVec3f color(1);
  api.GetIntensityAttr().Get(&intensity,at);api.GetExposureAttr().Get(&exposure,at);
  api.GetColorAttr().Get(&color,at);api.GetEnableColorTemperatureAttr().Get(&kelvin,at);
  api.GetColorTemperatureAttr().Get(&temperature,at);api.GetNormalizeAttr().Get(&normalize,at);
  if(!std::isfinite(intensity)||intensity<0||!std::isfinite(exposure)||std::abs(exposure)>64)
    throw std::runtime_error("Invalid light intensity/exposure");
  if(kelvin) {
    if(!std::isfinite(temperature)||temperature<1000||temperature>10000)
      throw std::runtime_error("Light color temperature outside 1000..10000 K profile");
    color=GfCompMult(color,UsdLuxBlackbodyTemperatureAsRgb(temperature));
  }
  double scale=double(intensity)*std::exp2(double(exposure));
  GfVec3d direction(0,1,0); float angle=0;
  if(type=="DistantLight") {
    prim.GetAttribute(TfToken("inputs:angle")).Get(&angle,at);
    if(!std::isfinite(angle)||angle<0||angle>=180) return JsValue();
    if(!normalize && angle>0) { double sine=std::sin(double(angle)*3.141592653589793/360); scale*=3.141592653589793*sine*sine; }
    direction=UsdGeomXformable(prim).ComputeLocalToWorldTransform(at).TransformDir(GfVec3d(0,0,1));
    if(UsdGeomGetStageUpAxis(prim.GetStage())==UsdGeomTokens->z)
      direction=GfVec3d(direction[0],direction[2],-direction[1]);
    if(direction.GetLength()<1e-12) throw std::runtime_error("Degenerate light transform");
    direction.Normalize();
  }
  JsArray rgb,dir;
  for(int i=0;i<3;++i) {
    double c=double(color[i])*scale;
    if(!std::isfinite(c)||c<0||c>60000) throw std::runtime_error("Cooked light exceeds 0..60000 linear RGB range");
    rgb.emplace_back(c);dir.emplace_back(direction[i]);
  }
  return JsValue(JsObject{{"id",JsValue(prim.GetPath().GetString())},{"type",JsValue(type)},
    {"rgb",JsValue(rgb)},{"direction",JsValue(dir)},{"time",JsValue(time)},
    {"angle",JsValue(double(angle))},{"policy",JsValue(type=="DistantLight"?
      "Directional approximation with normal-incidence illuminance; finite source shape and soft-shadow size are not reproduced":
      "Constant linear RGB distant radiance projected into Atlas SH")}});
}

static JsValue atlasPointLight(const UsdPrim &prim,double time) {
  if(prim.GetTypeName()!=TfToken("SphereLight")) return JsValue();
  bool point=false; prim.GetAttribute(TfToken("treatAsPoint")).Get(&point);
  if(!point) return JsValue();
  UsdLuxLightAPI api(prim); UsdTimeCode at(time);
  if(UsdGeomImageable(prim).ComputeVisibility(at)==UsdGeomTokens->invisible) return JsValue();
  for(auto a:prim.GetAttributes()) if(a.HasAuthoredConnections()) return JsValue();
  for(auto r:prim.GetRelationships()) if(r.HasAuthoredTargets()) return JsValue();
  // Animated local lights need a separate runtime track; do not silently freeze them.
  for(auto p=prim;p && !p.IsPseudoRoot();p=p.GetParent())
    for(auto a:p.GetAttributes()) if(a.ValueMightBeTimeVarying()) return JsValue();
  float intensity=1,exposure=0,radius=.5,temperature=6500,diffuse=1,specular=1;
  bool normalize=false,kelvin=false; GfVec3f color(1);
  api.GetIntensityAttr().Get(&intensity,at); api.GetExposureAttr().Get(&exposure,at);
  api.GetColorAttr().Get(&color,at); api.GetNormalizeAttr().Get(&normalize,at);
  api.GetDiffuseAttr().Get(&diffuse,at); api.GetSpecularAttr().Get(&specular,at);
  if(diffuse!=1||specular!=1) return JsValue();
  api.GetEnableColorTemperatureAttr().Get(&kelvin,at); api.GetColorTemperatureAttr().Get(&temperature,at);
  prim.GetAttribute(TfToken("inputs:radius")).Get(&radius,at);
  if(!std::isfinite(intensity)||intensity<0||!std::isfinite(exposure)||std::abs(exposure)>64||!std::isfinite(radius)||radius<0)
    throw std::runtime_error("Invalid point light inputs");
  if(kelvin) {
    if(!std::isfinite(temperature)||temperature<1000||temperature>10000)throw std::runtime_error("Invalid point light temperature");
    color=GfCompMult(color,UsdLuxBlackbodyTemperatureAsRgb(temperature));
  }
  auto matrix=UsdGeomXformable(prim).ComputeLocalToWorldTransform(at);
  GfVec3d axes[3]={matrix.TransformDir(GfVec3d(1,0,0)),
                  matrix.TransformDir(GfVec3d(0,1,0)),matrix.TransformDir(GfVec3d(0,0,1))};
  double scale=axes[0].GetLength();
  if(!std::isfinite(scale)||scale<1e-12)throw std::runtime_error("Degenerate point light transform");
  for(int i=0;i<3;++i) {
    if(!std::isfinite(axes[i].GetLength())||std::abs(axes[i].GetLength()/scale-1)>1e-5) return JsValue();
    for(int j=0;j<i;++j) if(std::abs(GfDot(axes[i]/scale,axes[j]/scale))>1e-5) return JsValue();
  }
  double units=UsdGeomGetStageMetersPerUnit(prim.GetStage());
  auto position=matrix.Transform(GfVec3d(0))*units;
  auto direction=matrix.TransformDir(GfVec3d(0,0,-1));
  if(direction.GetLength()<1e-12)throw std::runtime_error("Degenerate point light transform");
  direction.Normalize();
  if(UsdGeomGetStageUpAxis(prim.GetStage())==UsdGeomTokens->z) {
    position=GfVec3d(position[0],position[2],-position[1]);
    direction=GfVec3d(direction[0],direction[2],-direction[1]);
  }
  float cone=180,softness=0,focus=0;
  auto angle=prim.GetAttribute(TfToken("inputs:shaping:cone:angle"));
  if(angle) angle.Get(&cone,at);
  auto soft=prim.GetAttribute(TfToken("inputs:shaping:cone:softness")); if(soft)soft.Get(&softness,at);
  auto focused=prim.GetAttribute(TfToken("inputs:shaping:focus")); if(focused)focused.Get(&focus,at);
  if(focus!=0) return JsValue();
  if(!std::isfinite(cone)||cone<=0||cone>180||!std::isfinite(softness)||softness<0||softness>1)
    throw std::runtime_error("Invalid spot cone");
  double gain=intensity*std::exp2(double(exposure))*(normalize?.25:3.141592653589793*std::pow(radius*units*scale,2));
  JsArray rgb,pos,dir;
  for(int i=0;i<3;++i) {
    double c=double(color[i])*gain;
    if(!std::isfinite(c)||c<0||c>1e9||!std::isfinite(position[i]))throw std::runtime_error("Local light values exceed runtime range");
    rgb.emplace_back(c);pos.emplace_back(position[i]);dir.emplace_back(direction[i]);
  }
  double outer=cone==180?-1:std::cos(cone*3.141592653589793/180);
  double inner=cone==180?-1:std::cos(cone*(1-softness)*3.141592653589793/180);
  return JsValue(JsObject{{"id",JsValue(prim.GetPath().GetString())},{"position",JsValue(pos)},
    {"direction",JsValue(dir)},{"intensity",JsValue(rgb)},{"inner",JsValue(inner)},{"outer",JsValue(outer)},
    {"policy",JsValue("Static unshadowed far-field point approximation for treatAsPoint sphere; inverse-square falloff; smooth cone approximation")}});
}
