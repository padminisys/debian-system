# Preseed File Syntax Fix

## Issue
The Debian installer was failing with error:
```
Failed to process the preconfiguration file
The installer failed to process the preconfiguration file from file:///cdrom/preseed.cfg. 
The file may be corrupt.
```

## Root Cause
The preseed file contained **shell script syntax errors** in the `late_command` section:

1. **Incorrect awk syntax**: `awk "{print \$1}"` - The braces were escaped incorrectly
2. **Heredoc quoting issues**: Heredoc delimiters like `<< "EOF"` need special escaping when embedded in preseed

## Fixes Applied

### 1. AWK Command Syntax (Lines 127, 280)
**Before:**
```bash
ROOT_DEV=$(mount | grep "on /target " | awk "{print \$1}")
```

**After:**
```bash
ROOT_DEV=$(mount | grep "on /target " | awk '"'"'{print $1}'"'"')
```

### 2. Heredoc Delimiters (Multiple locations)
**Before:**
```bash
cat > /target/etc/fstab << "EOF"
```

**After:**
```bash
cat > /target/etc/fstab << '"'"'EOF'"'"'
```

## Technical Explanation

When embedding shell scripts in preseed files, special quoting is required because:
- The preseed parser processes the entire `late_command` as a single string
- Shell metacharacters need proper escaping to survive the preseed parser
- The pattern `'"'"'` effectively breaks out of single quotes, adds a single quote, and re-enters single quotes

## Verification

The corrected preseed file has been:
1. ✅ Syntax validated
2. ✅ Embedded in new ISO: `debian-12.12-btrfs-automated.iso`
3. ✅ Ready for USB installation

## Next Steps

1. **Flash the corrected ISO to USB:**
   ```bash
   sudo dd if=output/debian-12.12-btrfs-automated.iso of=/dev/sdX bs=4M status=progress conv=fsync
   ```

2. **Boot and test** - The installation should now proceed without preseed errors

3. **Verify post-installation** - After successful install, check:
   ```bash
   system-info
   btrfs subvolume list /
   snapper list
   ```

## Files Modified
- [`preseed/btrfs-automated.cfg`](../preseed/btrfs-automated.cfg) - Fixed shell syntax errors
- ISO rebuilt: `output/debian-12.12-btrfs-automated.iso`