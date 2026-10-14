// Numeric tuples retain their authored USD precision and role. Quaternion
// components use x,y,z,w; authored orientations are normalized as one tuple.
static std::vector<double> numericComponents(const VtValue &v) {
  if(v.IsHolding<float>())return {double(v.UncheckedGet<float>())};
  if(v.IsHolding<double>())return {v.UncheckedGet<double>()};
#define ATLAS_VECTOR_COMPONENTS(T,N) if(v.IsHolding<T>()){auto a=v.UncheckedGet<T>();std::vector<double> out;for(int i=0;i<N;++i)out.push_back(double(a[i]));return out;}
  ATLAS_VECTOR_COMPONENTS(GfVec2f,2) ATLAS_VECTOR_COMPONENTS(GfVec2d,2)
  ATLAS_VECTOR_COMPONENTS(GfVec3f,3) ATLAS_VECTOR_COMPONENTS(GfVec3d,3)
  ATLAS_VECTOR_COMPONENTS(GfVec3h,3)
#undef ATLAS_VECTOR_COMPONENTS
#define ATLAS_QUAT_COMPONENTS(T) if(v.IsHolding<T>()){auto q=v.UncheckedGet<T>();auto a=q.GetImaginary();return {double(a[0]),double(a[1]),double(a[2]),double(q.GetReal())};}
  ATLAS_QUAT_COMPONENTS(GfQuatf) ATLAS_QUAT_COMPONENTS(GfQuatd)
#undef ATLAS_QUAT_COMPONENTS
#define ATLAS_ARRAY_COMPONENTS(T) if(v.IsHolding<VtArray<T>>()){const auto &a=v.UncheckedGet<VtArray<T>>();if(a.empty() || a.size()>64)throw std::runtime_error("Animation arrays require 1..64 entries");std::vector<double> out;for(const auto &n:a){auto part=numericComponents(VtValue(n));out.insert(out.end(),part.begin(),part.end());}return out;}
  ATLAS_ARRAY_COMPONENTS(float) ATLAS_ARRAY_COMPONENTS(GfVec3f)
  ATLAS_ARRAY_COMPONENTS(GfVec3h) ATLAS_ARRAY_COMPONENTS(GfQuatf)
#undef ATLAS_ARRAY_COMPONENTS
  throw std::runtime_error("Numeric profile supports float/double scalars, two/three-component vectors and float/double orientations");
}
static bool numericArray(const VtValue &v) {
  return v.IsHolding<VtFloatArray>() || v.IsHolding<VtVec3fArray>() || v.IsHolding<VtVec3hArray>() || v.IsHolding<VtQuatfArray>();
}
static bool numericValue(const VtValue &v) {
  return v.IsHolding<float>() || v.IsHolding<double>() || v.IsHolding<GfVec2f>() || v.IsHolding<GfVec2d>() ||
    v.IsHolding<GfVec3f>() || v.IsHolding<GfVec3d>() || v.IsHolding<GfVec3h>() || v.IsHolding<GfQuatf>() || v.IsHolding<GfQuatd>() || numericArray(v);
}
static VtValue numericTuple(const VtValue &prototype,const std::vector<double> &a) {
  if(a.size()!=numericComponents(prototype).size())throw std::runtime_error("Numeric tuple has the wrong component count");
  bool single=prototype.IsHolding<float>() || prototype.IsHolding<GfVec2f>() || prototype.IsHolding<GfVec3f>() || prototype.IsHolding<GfQuatf>();
  for(double n:a)if(!std::isfinite(n) || (single && std::abs(n)>std::numeric_limits<float>::max()))throw std::runtime_error("Numeric component is non-finite or outside its authored precision");
#define ATLAS_ARRAY_TUPLE(T) if(prototype.IsHolding<VtArray<T>>()){auto result=prototype.UncheckedGet<VtArray<T>>();size_t width=numericComponents(VtValue(result[0])).size();for(size_t i=0;i<result.size();++i)result[i]=numericTuple(VtValue(result[i]),std::vector<double>(a.begin()+i*width,a.begin()+(i+1)*width)).Get<T>();return VtValue(result);}
  ATLAS_ARRAY_TUPLE(float) ATLAS_ARRAY_TUPLE(GfVec3f)
  ATLAS_ARRAY_TUPLE(GfVec3h) ATLAS_ARRAY_TUPLE(GfQuatf)
#undef ATLAS_ARRAY_TUPLE
  if(prototype.IsHolding<float>())return VtValue(float(a[0]));
  if(prototype.IsHolding<double>())return VtValue(a[0]);
  if(prototype.IsHolding<GfVec2f>())return VtValue(GfVec2f(a[0],a[1]));
  if(prototype.IsHolding<GfVec2d>())return VtValue(GfVec2d(a[0],a[1]));
  if(prototype.IsHolding<GfVec3f>())return VtValue(GfVec3f(a[0],a[1],a[2]));
  if(prototype.IsHolding<GfVec3d>())return VtValue(GfVec3d(a[0],a[1],a[2]));
  if(prototype.IsHolding<GfVec3h>()){for(double n:a)if(std::abs(n)>65504)throw std::runtime_error("Scale exceeds half precision");return VtValue(GfVec3h(a[0],a[1],a[2]));}
  double largest=0;for(double n:a)largest=std::max(largest,std::abs(n));
  if(largest==0)throw std::runtime_error("Orientation requires a nonzero quaternion");
  double norm=0;for(double n:a)norm+=(n/largest)*(n/largest);norm=std::sqrt(norm);
  if(prototype.IsHolding<GfQuatf>())return VtValue(GfQuatf(a[3]/largest/norm,GfVec3f(a[0]/largest/norm,a[1]/largest/norm,a[2]/largest/norm)));
  return VtValue(GfQuatd(a[3]/largest/norm,GfVec3d(a[0]/largest/norm,a[1]/largest/norm,a[2]/largest/norm)));
}
static VtValue numericInput(const VtValue &prototype,const JsValue &input) {
  std::vector<double> values;
  if(input.IsArray()){for(const auto &v:input.GetJsArray())values.push_back(number(v));}
  else values.push_back(number(input));
  return numericTuple(prototype,values);
}
