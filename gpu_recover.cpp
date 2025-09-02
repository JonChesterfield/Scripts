#if 0
bin/clang++ -std=c++17 -stdlib=libc++  -O1 gpu_recover.cpp -static -lc++abi -pthread -fuse-ld=lld -o gpu_recover
chown root gpu_recover
chmod u+s gpu_recover
mv gpu_recover bin/
exit 0
#endif

#include <cstdio>
#include <filesystem>

void readFile(std::string path) {
  // ifstream didn't work, was too sure the file was size zero
  FILE *file = fopen(path.c_str(), "r");
  if (file) {
    int chr;
    while ((chr = getc(file)) != EOF) {
      printf("%c", chr);
    }
  }
  fclose(file);
}

int main(void) {

  for (const auto &dirEntry : std::filesystem::recursive_directory_iterator(
           "/sys/kernel/debug/dri/")) {
    auto str = dirEntry.path().string();
    if (str.find("/amdgpu_gpu_recover") != std::string::npos) {
      printf("Located %s\n", str.c_str());
      readFile(str);
    }
  }
}
