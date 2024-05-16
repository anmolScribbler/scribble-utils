#!/bin/bash

# Function to encrypt the credentials files
encrypt() {
    if [ $# -lt 2 ]; then
        echo "Usage: encrypt-util.sh encrypt <zipfile> file1 [file2..]"
        return
    fi
    echo "Encrypting given files using user provided password."
    echo "Please provide the password of your choice."
    read -p "Password: " PASSWORD

    ZIPFILE=$1
    shift

    # Encrypt each file provided as arguments
    for file in "$@"; do
        7z a -p"${PASSWORD}" $ZIPFILE "$file"
    done

    echo "Encrypted creds in $ZIPFILE"

    echo -n "$PASSWORD" | base64 > "keyfile"
}

# Function to decrypt the credentials files and extract to 'decrypted' directory
decrypt() {
    if [ $# -lt 1 ]; then
        echo "encrypt-util.sh decrypt <zipfile>"
        return
    fi

    # Read password from keyfile
    if [ ! -f "keyfile" ]; then
        echo "Keyfile not found. Please run 'encrypt' first."
        return
    fi

    PASSWORD=$(cat "keyfile" | base64 --decode)

    # Create 'decrypted' directory if it doesn't exist
    mkdir -p decrypted

    # Decrypt with password and extract to 'decrypted' directory
    ZIPFILE=$1
    7z x -p"${PASSWORD}" -o"decrypted" $ZIPFILE

    echo "Decrypted creds from $ZIPFILE to 'decrypted' directory"
}

# Function to decrypt cred.zip file and compare decrypted files with original files
test_decrypt() {
    # Decrypt cred.zip file
    echo "Testing decryption using given password."
    decrypt "cred.zip"

    mismatch_count=0

    # Iterate over each file in decrypted directory
    for file in decrypted/*; do
        filename=$(basename "$file")

        # Compare decrypted file with corresponding file in pwd
        if ! cmp -s "./$filename" "$file"; then
            echo "File $filename does not match"
            ((mismatch_count++))
        else
            echo "File $filename matches"
        fi
    done

    if [ $mismatch_count -eq 0 ]; then
        echo "All files match"
        return $mismatch_count
    else
        echo "Total mismatched files: $mismatch_count"
        return $mismatch_count
    fi
}

# Function to remove decrypted files and directory
cleanup() {
    # Remove original files that were encrypted
    for file in "$@"; do
        echo "Removing original file: $file"
        rm -f "$file"
    done
    echo "Removing decrypted directory."
    rm -rf decrypted
    echo "Cleanup done."
}

# Main flow
encrypt "cred.zip" $@
test_decrypt
result=$?

if [ "$result" -eq "0" ]; then
    echo "Encryption, decryption, and testing successful."
    echo "Cleaning up the files."
    cleanup $@
else
    echo "Testing found mismatches. Check output for details."
fi
