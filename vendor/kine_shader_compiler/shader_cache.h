#pragma once
#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <string>
#include <string_view>
#include <vector>

namespace kine_shader_cache {
inline std::atomic<uint64_t> hits{0}, misses{0}, writes{0}, corrupt{0}, compile_ns{0};
inline std::mutex io_mutex;
inline std::atomic<uint64_t> sequence{0};
constexpr size_t max_blob = 16 * 1024 * 1024;
constexpr size_t max_files = 256;
constexpr uint64_t max_disk = 128 * 1024 * 1024;
using Digest = std::array<uint8_t, 32>;
inline Digest digest(std::string_view input) {
    constexpr uint32_t k[64] = {
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2};
    uint32_t h[8]={0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19};
    auto r=[](uint32_t x,int n){return (x>>n)|(x<<(32-n));};
    const size_t total=(input.size()+9+63)/64*64;
    for(size_t offset=0;offset<total;offset+=64){
        uint32_t w[64]{};
        for(size_t i=0;i<64;++i){size_t p=offset+i; uint8_t b=0;
            if(p<input.size())b=uint8_t(input[p]);else if(p==input.size())b=128;
            else if(p>=total-8)b=uint8_t((uint64_t(input.size())*8)>>((total-1-p)*8));
            w[i/4]|=uint32_t(b)<<(24-8*(i%4));}
        for(int i=16;i<64;++i)w[i]=w[i-16]+(r(w[i-15],7)^r(w[i-15],18)^(w[i-15]>>3))+w[i-7]+(r(w[i-2],17)^r(w[i-2],19)^(w[i-2]>>10));
        uint32_t a=h[0],b=h[1],c=h[2],d=h[3],e=h[4],f=h[5],g=h[6],v=h[7];
        for(int i=0;i<64;++i){uint32_t t1=v+(r(e,6)^r(e,11)^r(e,25))+((e&f)^(~e&g))+k[i]+w[i];uint32_t t2=(r(a,2)^r(a,13)^r(a,22))+((a&b)^(a&c)^(b&c));v=g;g=f;f=e;e=d+t1;d=c;c=b;b=a;a=t1+t2;}
        uint32_t result[]={a,b,c,d,e,f,g,v};for(int i=0;i<8;++i)h[i]+=result[i];
    }
    Digest out{};for(int i=0;i<32;++i)out[i]=uint8_t(h[i/4]>>(24-8*(i%4)));return out;
}
inline std::string hex(const Digest& d){constexpr char chars[]="0123456789abcdef";std::string out;out.reserve(64);for(auto b:d){out+=chars[b>>4];out+=chars[b&15];}return out;}
inline std::filesystem::path directory(){
    if(const char* p=std::getenv("KINE_SHADER_CACHE_DIR")){if(!*p||std::strcmp(p,"off")==0)return {};return p;}
#if defined(_WIN32)
    if(const char* p=std::getenv("LOCALAPPDATA"))return std::filesystem::path(p)/"Kinemium"/"shaders-v1";
#else
    if(const char* p=std::getenv("XDG_CACHE_HOME"))return std::filesystem::path(p)/"kinemium"/"shaders-v1";
    if(const char* p=std::getenv("HOME"))return std::filesystem::path(p)/".cache"/"kinemium"/"shaders-v1";
#endif
    return {};
}
inline Digest key(std::string_view kind,std::string_view source){
    std::string text="kinemium-shader-cache-v1:" __DATE__ ":" __TIME__ ":";text+=kind;text+='\0';text+=source;return digest(text);
}
inline bool read(const Digest& key,std::vector<uint8_t>& out) noexcept {
    try{std::lock_guard lock(io_mutex);auto dir=directory();if(dir.empty()){++misses;return false;}
        auto path=dir/(hex(key)+".bin");std::ifstream file(path,std::ios::binary|std::ios::ate);
        if(!file){++misses;return false;}auto size=file.tellg();
        if(size<72||size>std::streamoff(max_blob+72)){++corrupt;++misses;return false;}
        file.seekg(0);std::vector<uint8_t> data(size_t(size),uint8_t{});file.read(reinterpret_cast<char*>(data.data()),size);
        if(!file||std::memcmp(data.data(),"KSCACHE1",8)||std::memcmp(data.data()+8,key.data(),32)){++corrupt;++misses;return false;}
        auto sum=digest({reinterpret_cast<const char*>(data.data()+72),data.size()-72});
        if(std::memcmp(data.data()+40,sum.data(),32)){++corrupt;++misses;return false;}
        out.assign(data.begin()+72,data.end());++hits;return true;
    }catch(...){++misses;return false;}
}
inline void write(const Digest& key,const void* bytes,size_t size) noexcept {
    if(!bytes||!size||size>max_blob)return;
    try{std::lock_guard lock(io_mutex);auto dir=directory();if(dir.empty())return;std::error_code ec;
        std::filesystem::create_directories(dir,ec);if(ec)return;
        size_t files=0;uint64_t total=0;
        for(const auto& entry:std::filesystem::directory_iterator(dir,ec)){
            if(entry.path().extension()!=".bin")continue;++files;total+=entry.file_size(ec);if(ec)return;}
        auto path=dir/(hex(key)+".bin");if(files>=max_files||total+size+72>max_disk)return;
        auto temp=path;temp+=".tmp-"+std::to_string(std::chrono::steady_clock::now().time_since_epoch().count())+"-"+std::to_string(++sequence);
        auto sum=digest({static_cast<const char*>(bytes),size});
        {std::ofstream file(temp,std::ios::binary|std::ios::trunc);if(!file)return;file.write("KSCACHE1",8);file.write(reinterpret_cast<const char*>(key.data()),32);file.write(reinterpret_cast<const char*>(sum.data()),32);file.write(static_cast<const char*>(bytes),std::streamsize(size));file.flush();if(!file){file.close();std::filesystem::remove(temp,ec);return;}}
        std::filesystem::rename(temp,path,ec);if(ec){std::filesystem::remove(temp,ec);return;}++writes;
    }catch(...){}
}
struct Timer{std::chrono::steady_clock::time_point start=std::chrono::steady_clock::now();~Timer(){compile_ns+=uint64_t(std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now()-start).count());}};
}
