#!/bin/bash

echo "Scanning INDI drivers and sorting dependencies..."
echo "------------------------------------------------------------"

tmp_file=$(mktemp)

# Loop through all files in /usr/bin starting with "indi_"
for file in /usr/bin/indi_*; do
    [ -x "$file" ] || continue
    # Extract only the library filenames that are reported as 'not found'
    ldd "$file" 2>/dev/null | grep "not found" | awk '{print $1}' >> "$tmp_file"
done

# Sort and deduplicate the list of missing libraries
missing_libs=$(sort -u "$tmp_file")
rm "$tmp_file"

if [ -z "$missing_libs" ]; then
    echo "🎉 Great news! No missing libraries detected across any INDI drivers."
    exit 0
fi

# Define arrays for tracking fixes
declare -A sim_fixes
no_matches=""

# Loop through the missing libraries and look for similar files in the system
for lib in $missing_libs; do
    # Strip the extension and version (e.g., "libraw.so.23" -> "libraw")
    base_name=$(echo "$lib" | sed -E 's/\.so(\.[0-9]+)*$//')
    
    raw_matches=$(ls /lib/aarch64-linux-gnu/${base_name}* 2>/dev/null)
    
    if [ -n "$raw_matches" ]; then
        # Take the first actual match found in the directory
        actual_lib=$(echo "$raw_matches" | head -n 1)
        sim_fixes["$lib"]="$actual_lib"
    else
        no_matches+="$lib "
    fi
done

# Output List 1
echo -e "\n📂 [LIST 1] FOUND SIMILAR (Version mismatches)"
echo "----------------------------------------------------------------------------------------"
if [ ${#sim_fixes[@]} -eq 0 ]; then
    echo "None found."
else
    for lib in "${!sim_fixes[@]}"; do
        printf "%-30s | Found: %s\n" "$lib" "$(basename "${sim_fixes[$lib]}")"
    done
fi

# Output List 2
echo -e "\n❌ [LIST 2] NO MATCHES AT ALL (Missing packages)"
echo "----------------------------------------------------------------------------------------"
if [ -z "$no_matches" ]; then
    echo "None found."
else
    for lib in $no_matches; do
        echo "$lib"
    done
fi

echo -e "\n------------------------------------------------------------"

# --- ACTION 1: Fix Symlinks ---
if [ ${#sim_fixes[@]} -gt 0 ]; then
    read -p "Do you want to create symlinks for List 1? (y/n): " answer_sym
    if [[ "$answer_sym" =~ ^[Yy]$ ]]; then
        echo "Creating symlinks..."
        for lib in "${!sim_fixes[@]}"; do
            target="${sim_fixes[$lib]}"
            echo "Linking /lib/aarch64-linux-gnu/$lib -> $target"
            sudo ln -sf "$target" "/lib/aarch64-linux-gnu/$lib"
        done
    fi
fi

# --- ACTION 2: Fix Apt Packages ---
if [ -n "$no_matches" ]; then
    read -p "Do you want to attempt installing missing system packages for List 2? (y/n): " answer_apt
    if [[ "$answer_apt" =~ ^[Yy]$ ]]; then
        echo "Identifying and installing packages..."
        
        # Build list of packages to install based on your specific missing libs
        packages_to_install=""
        [[ "$no_matches" =~ "libavcodec" ]] && packages_to_install+="libavcodec59 libavdevice59 libavformat59 libavutil57 libswscale6 "
        [[ "$no_matches" =~ "libgps" ]] && packages_to_install+="libgps28 "
        [[ "$no_matches" =~ "libzmq" ]] && packages_to_install+="libzmq5 "
        [[ "$no_matches" =~ "libgsl" ]] && packages_to_install+="libgsl27 "
        
        if [ -n "$packages_to_install" ]; then
            sudo apt update && sudo apt install -y $packages_to_install
        else
            echo "No mapped packages found for the missing libraries."
        fi
    fi
fi

echo -e "\nAll requested actions completed. Run the script again to verify."

