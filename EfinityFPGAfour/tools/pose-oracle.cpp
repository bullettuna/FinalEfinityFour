// Compile against the user's original source without modifying that project.
#define main software_prototype_main
#include "main.cpp"
#undef main
int main(int argc, char** argv) {
    if (argc != 3) return 2;
    const Image input = read_pnm(argv[1]);
    const auto mask = threshold_dark(input, 127);
    Box box;
    box.xmin=0; box.xmax=input.width-1;
    box.ymin=0; box.ymax=input.height-1;
    box.pixels=std::count(mask.begin(), mask.end(), std::uint8_t(1));
    const auto result=identify_pose(mask,input.width,box,argv[2]);
    std::cout << result.best_pose << ' ' << result.best_similarity << ' '
              << result.runner_up_similarity << '\n';
    for (const auto& s:result.scores)
        std::cout << s.intersection << ' ' << s.combined << ' ' << s.similarity_per_mille << '\n';
}
