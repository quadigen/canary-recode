#include "../vendor/kine_shader_compiler/shader_cache.h"
#include <cassert>
#include <iostream>
int main() {
 using namespace kine_shader_cache;
 assert(hex(digest(""))=="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
 assert(hex(digest("abc"))=="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
 auto a=key("compiler-A","shader"); auto b=key("compiler-B","shader");assert(a!=b);
 std::vector<uint8_t> data;assert(!read(a,data));
 write(a,"hello",5);assert(read(a,data));assert(std::string(data.begin(),data.end())=="hello");
 assert(!read(b,data));
 auto path=directory()/(hex(a)+".bin");
 {std::fstream f(path,std::ios::binary|std::ios::in|std::ios::out);f.seekp(73);f.put('X');}
 assert(!read(a,data));assert(corrupt==1);
 write(a,"repaired",8);assert(read(a,data));assert(std::string(data.begin(),data.end())=="repaired");
 std::cout<<"SHADER_CACHE_UNIT_PASSED hits="<<hits<<" misses="<<misses<<" corruption="<<corrupt<<"\n";
}
