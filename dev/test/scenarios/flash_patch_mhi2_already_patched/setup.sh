. "$(dirname "${BASH_SOURCE[0]}")/../../lib/setup.sh"
place_patch_folder
flash_image "$SIM_PROFILE/stage2-patched.ifs"
