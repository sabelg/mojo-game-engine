#pragma once
#include <OpenColorIO/OpenColorIO.h>
#include <pxr/base/gf/vec3f.h>
#include <string>
namespace AtlasOCIO = OCIO_NAMESPACE;
// Built-in OCIO configuration is versioned with the pinned SDK. No user scripts,
// network paths or external LUT files are loaded by this conversion profile.
static pxr::GfVec3f atlasLinearColor(pxr::GfVec3f color,const std::string &space) {
  if(space.empty()||space=="lin_rec709") return color;
  static const auto config=AtlasOCIO::Config::CreateFromBuiltinConfig("ocio://cg-config-v4.0.0_aces-v2.0_ocio-v2.5");
  auto cpu=config->getProcessor(space.c_str(),"lin_rec709")->getDefaultCPUProcessor();
  float values[3]={color[0],color[1],color[2]}; cpu->applyRGB(values);
  return pxr::GfVec3f(values[0],values[1],values[2]);
}
