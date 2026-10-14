// Versioned, bounded and crash-safe authoring workspaces. No source writes.
// Included after the stage service's JSON helpers; all paths are filesystem paths.
#include <array>
#include <cstdint>
#include <sstream>
#include <sys/file.h>
#include <signal.h>
#include <cerrno>

namespace workspace {
// OpenUSD's path rewrite replaces sublayer paths and resets their offsets.
// Preserve both time mappings and empty entries in asset-path arrays.
inline void repath(const SdfLayerHandle &layer,const UsdUtilsModifyAssetPathFn &fn) {
  auto offsets=layer->GetSubLayerOffsets();UsdUtilsModifyAssetPaths(layer,fn,true);
  if(layer->GetSubLayerPaths().size()!=offsets.size())throw std::runtime_error("Asset relocation changed sublayer topology");
  for(size_t i=0;i<offsets.size();++i)layer->SetSubLayerOffset(offsets[i],int(i));
}
constexpr size_t manifestLimit=1024*1024, layerLimit=32*1024*1024;
constexpr uintmax_t fileLimit=64*1024*1024, bundleLimit=256*1024*1024;
// Standard SHA-256; keep the service independent of an extra crypto shared library.
inline std::string digest(const std::string &text) {
  static const uint32_t k[64]={
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2};
  std::array<uint32_t,8> h={0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19};
  auto rotate=[](uint32_t x,unsigned n){return (x>>n)|(x<<(32-n));};
  size_t count=(text.size()+9+63)/64;uint64_t bits=uint64_t(text.size())*8;
  for(size_t block=0;block<count;++block) {
    uint32_t w[64]={};
    for(size_t i=0;i<64;++i) {
      size_t pos=block*64+i;uint32_t b=0;
      if(pos<text.size())b=static_cast<unsigned char>(text[pos]);
      else if(pos==text.size())b=128;
      else if(pos>=count*64-8)b=(bits>>(8*(count*64-1-pos)))&255;
      w[i/4]|=b<<(24-8*(i%4));
    }
    for(int i=16;i<64;++i) {
      uint32_t a=w[i-15],b=w[i-2];
      w[i]=w[i-16]+(rotate(a,7)^rotate(a,18)^(a>>3))+w[i-7]+(rotate(b,17)^rotate(b,19)^(b>>10));
    }
    auto s=h;
    for(int i=0;i<64;++i) {
      uint32_t t1=s[7]+(rotate(s[4],6)^rotate(s[4],11)^rotate(s[4],25))+((s[4]&s[5])^(~s[4]&s[6]))+k[i]+w[i];
      uint32_t t2=(rotate(s[0],2)^rotate(s[0],13)^rotate(s[0],22))+((s[0]&s[1])^(s[0]&s[2])^(s[1]&s[2]));
      for(int j=7;j>0;--j)s[j]=s[j-1];s[4]+=t1;s[0]=t1+t2;
    }
    for(int i=0;i<8;++i)h[i]+=s[i];
  }
  std::string result;const char *hex="0123456789abcdef";
  for(auto word:h)for(int shift=28;shift>=0;shift-=4)result+=hex[(word>>shift)&15];return result;
}
inline std::string read(const fs::path &path,size_t limit) {
  if(!fs::is_regular_file(path) || fs::file_size(path)>limit)throw std::runtime_error("Missing or oversized workspace dependency: "+path.string());
  std::ifstream input(path,std::ios::binary);std::string result;std::array<char,65536> block;
  while(input) {input.read(block.data(),block.size());result.append(block.data(),size_t(input.gcount()));
    if(result.size()>limit)throw std::runtime_error("Workspace dependency exceeded byte limit: "+path.string());}
  if(!input.eof())throw std::runtime_error("Cannot read workspace dependency: "+path.string());return result;
}
inline std::string json(const JsValue &v) {std::ostringstream stream;{JsWriter writer(stream);JsWriteValue(&writer,v);}return stream.str()+"\n";}
inline Object object(const JsValue &v) {if(!v.IsObject())throw std::runtime_error("Expected workspace object");return v.GetJsObject();}
inline JsArray array(const JsValue &v,size_t max) {if(!v.IsArray() || v.GetJsArray().size()>max)throw std::runtime_error("Invalid workspace array budget");return v.GetJsArray();}
inline Object manifest(const fs::path &path) {
  auto text=read(path,manifestLimit);int depth=0;bool quoted=false,escaped=false;
  for(char c:text) {if(quoted){if(escaped)escaped=false;else if(c=='\\')escaped=true;else if(c=='"')quoted=false;}
    else if(c=='"')quoted=true;else if(c=='{'||c=='['){if(++depth>16)throw std::runtime_error("Workspace JSON nesting exceeds 16");}else if(c=='}'||c==']')--depth;}
  JsParseError error;auto result=object(JsParseString(text,&error));
  if(string(field(result,"format"))!="atlas-usd-workspace" || (number(field(result,"version"))!=1 && number(field(result,"version"))!=2))
    throw std::runtime_error("Unsupported workspace format/version; preserve the project and use a compatible SDK");
  return result;
}
inline bool name(const std::string &n) {return !n.empty() && n.size()<=32 && n!="session" &&
  std::all_of(n.begin(),n.end(),[](unsigned char c){return (c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='_'||c=='-';});}
inline bool generation(const std::string &n) {return n.size()==34 && n.substr(0,2)=="g-" &&
  std::all_of(n.begin()+2,n.end(),[](char c){return (c>='0'&&c<='9')||(c>='a'&&c<='f');});}
inline fs::path owned(const fs::path &root,const std::string &relative,const std::string &gen) {
  fs::path p(relative);if(p.is_absolute() || p.lexically_normal()!=p || p.empty() || relative.size()>4096 ||
    std::any_of(relative.begin(),relative.end(),[](unsigned char c){return c<32 || c==127;}))throw std::runtime_error("Invalid owned workspace path");
  for(const auto &part:p)if(part==".." || part==".")throw std::runtime_error("Owned workspace path escapes project");
  if(p.parent_path()!=fs::path("generations")/gen || p.extension()!=".usda")throw std::runtime_error("Owned layer is outside the selected generation");
  auto current=root;for(const auto &part:p){current/=part;if(fs::is_symlink(fs::symlink_status(current)))throw std::runtime_error("Owned workspace paths must not be symlinks");}
  return current;
}
inline Object file(const fs::path &root,const fs::path &path,size_t limit) {
  auto data=read(path,limit);return Object{{"path",JsValue(fs::relative(path,root).generic_string())},{"bytes",JsValue(int64_t(data.size()))},{"sha256",JsValue(digest(data))}};
}
inline std::string checked(const fs::path &path,const Object &record,size_t limit) {
  auto data=read(path,limit);if(number(field(record,"bytes"))!=double(data.size()) || string(field(record,"sha256"))!=digest(data))
    throw std::runtime_error("Workspace dependency changed or checksum failed: "+path.string());return data;
}
inline void sync(const fs::path &path,bool directory=false) {
  int fd=::open(path.c_str(),O_RDONLY|(directory?O_DIRECTORY:0)|O_NOFOLLOW);
  if(fd<0)throw std::runtime_error("Cannot open workspace for synchronization: "+path.string());
  int rc=::fsync(fd);::close(fd);if(rc)throw std::runtime_error("Cannot synchronize workspace: "+path.string());
}
// Tests inject real process death or I/O failures at publication boundaries.
inline void fault(const std::string &point) {
  const char *setting=std::getenv("ATLAS_WORKSPACE_FAULT");if(!setting)return;
  if(std::string(setting)=="kill:"+point){::kill(getpid(),SIGKILL);_exit(137);}
  if(std::string(setting)=="error:"+point)throw std::runtime_error("Injected workspace I/O error at "+point);
}
inline void write(const fs::path &path,const std::string &data) {
  int fd=::open(path.c_str(),O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
  if(fd<0)throw std::runtime_error("Cannot create workspace file: "+path.string());
  size_t written=0;while(written<data.size()) {ssize_t n=::write(fd,data.data()+written,data.size()-written);
    if(n<0 && errno==EINTR)continue;if(n<=0){::close(fd);throw std::runtime_error("Cannot write workspace file: "+path.string());}written+=size_t(n);}
  int rc=::fsync(fd);::close(fd);if(rc)throw std::runtime_error("Cannot synchronize workspace file: "+path.string());
}
struct Lock {
  int fd=-1;
  explicit Lock(const fs::path &root) {
    fd=::open((root/"workspace.lock").c_str(),O_WRONLY|O_CREAT|O_NOFOLLOW,0600);
    if(fd<0)throw std::runtime_error("Cannot open workspace writer lock");
    if(::flock(fd,LOCK_EX|LOCK_NB)){::close(fd);fd=-1;throw std::runtime_error("Another writer is saving this workspace");}
  }
  ~Lock(){if(fd>=0)::close(fd);}
  Lock(const Lock &)=delete;
};
} // namespace workspace
