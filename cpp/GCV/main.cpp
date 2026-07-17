#define FPLS_SIMULATION_1D
#include "../1D/main_impl.h"

int main(int argc, char* argv[]) {
    try {
        return fpls_simulation_main(argc, argv);
    } catch (const std::exception& error) {
        std::cerr << "fPLS simulation failed: " << error.what() << '\n';
        return 2;
    }
}
