#!/bin/bash

echo "Scanning INDI drivers and checking /lib/aarch64-linux-gnu/..."
echo "------------------------------------------------------------"

# Temporary file to collect all unique missing libraries
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

# Print comparison table headers
printf "%-30s | %-40s\n" "❌ Missing Library Needed by INDI" "🔍 What actually exists in your system"
echo "----------------------------------------------------------------------------------------"

# Loop through the missing libraries and look for similar files in the system
for lib in $missing_libs; do
    # Strip the extension and version (e.g., "libraw.so.23" -> "libraw")
    base_name=$(echo "$lib" | sed -E 's/\.so(\.[0-9]+)*$//')
    
    # Search the system directory for anything matching that base name
    matches=$(ls /lib/aarch64-linux-gnu/${base_name}* 2>/dev/null | xargs -n1 basename)
    
    if [ -n "$matches" ]; then
        # If files exist but version doesn't match
        existing_list=$(echo "$matches" | tr '\n' ' ')
        printf "%-30s | Found similar: %-40s\n" "$lib" "$existing_list"
    else
        # If nothing even close exists
        printf "%-30s | No matches found at all.\n" "$lib"
    fi
done

