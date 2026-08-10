# SelahOS AUR Submission Guide

Submitting SelahOS packages to the Arch User Repository (AUR).

## Prerequisites

1. AUR account: https://aur.archlinux.org/
2. SSH key setup for AUR
3. `base-devel` package installed: `pacman -S base-devel`
4. `aurutils` (optional, for easier AUR operations): `pacman -S aurutils`

## Setup SSH Key for AUR

```bash
# Generate SSH key (if not already done)
ssh-keygen -t ed25519 -C "your-email@example.com"

# Add to AUR account at https://aur.archlinux.org/account/

# Test connection
ssh aur@aur.archlinux.org help
```

## Packages to Submit

1. **selahos-device-editors** (devices)
   - Main device editor applications
   - 7 GUI editors for Akai controllers

2. **selahos-device-bridge-web** (selahos-device-bridge-web)
   - Vue.js web interface
   - FastAPI integration

3. **selahos-device-scripting** (selahos-device-scripting)
   - Macro automation library
   - Python module and tools

## Initial Submission Process

### 1. Clone AUR Repository (first time only)

```bash
git clone ssh://aur@aur.archlinux.org/selahos-device-editors.git
cd selahos-device-editors
```

### 2. Prepare PKGBUILD

```bash
# Copy PKGBUILD from this repository
cp /path/to/tools/AUR/selahos-device-editors/PKGBUILD .

# Test PKGBUILD locally
makepkg -f

# Install to test
sudo pacman -U selahos-device-editors-*.pkg.tar.zst
```

### 3. Create .SRCINFO

```bash
# Install asp if not present
pacman -S asp

# Generate .SRCINFO
mksrcinfo

# Verify .SRCINFO was created
ls -la .SRCINFO
```

### 4. Commit and Push

```bash
git add PKGBUILD .SRCINFO
git commit -m "Initial commit: version 1.0.0"
git push origin master
```

## Updates to Existing Packages

### Update Version

```bash
# Pull latest
git pull origin master

# Edit PKGBUILD
nano PKGBUILD
# Update:
# - pkgver=X.Y.Z
# - pkgrel=1 (reset when version changes)
# - sha256sums (update hash)

# Generate new .SRCINFO
mksrcinfo

# Test
makepkg -f
makepkg -c  # Check for warnings

# Commit and push
git add PKGBUILD .SRCINFO
git commit -m "Update to version X.Y.Z"
git push origin master
```

### Increment Release Number (for bug fixes)

```bash
# Edit PKGBUILD
# Change pkgrel from N to N+1 (e.g., 1 → 2)

# Generate .SRCINFO
mksrcinfo

# Commit
git add PKGBUILD .SRCINFO
git commit -m "pkgrel bump: fix for [issue description]"
git push origin master
```

## Package Guidelines

### Architecture Support

- `arch=('x86_64')` for binaries/scripts with arch-specific needs
- `arch=('any')` for pure Python/web content
- Test on actual Arch system before submission

### Dependencies

**Device Editors (selahos-device-editors)**
- `python` (required)
- `python-pyqt6` (required)
- `python-mido` (required)

**Web Interface (selahos-device-bridge-web)**
- `python-fastapi` (required)
- `python-uvicorn` (required)
- Optional: `nginx` for reverse proxy

**Scripting (selahos-device-scripting)**
- `python` (required)
- `python-pydantic` (required)
- `python-fastapi` (optional, for API)

### Source URLs

Always use stable release URLs from GitHub:

```bash
source=("https://github.com/SelahOS/selahos-iso/releases/download/v${pkgver}/device-editors-v${pkgver}.tar.gz")
sha256sums=('SKIP')  # Will be filled after first build
```

### Testing Checklist

Before submission:
- [ ] `makepkg -f` completes without errors
- [ ] `makepkg -c` produces no warnings
- [ ] Generated binaries/scripts work correctly
- [ ] Dependencies are correctly listed
- [ ] No unnecessary files in package
- [ ] Man pages or docs included
- [ ] Post-install messages are helpful
- [ ] License files included (GPL3)

## Common Issues & Solutions

### "Invalid package signature"
- Ensure PKG files are in correct format
- Check sha256sums are properly calculated

### "Dependencies not found"
- Verify package names in official repos
- Check `-community` repos: `pacman -Ss name`
- Look for AUR alternatives if needed

### "PKGBUILD won't build"
- Run `makepkg -f --nocheck` to skip tests
- Check source URL is accessible
- Verify sha256sum matches actual file

### ".SRCINFO not committed"
- Always run `mksrcinfo` before commit
- Verify `.SRCINFO` changes in git diff

## Automated Updates (Future)

Once published, you can:

1. Set up GitHub Actions to automatically:
   - Create releases with assets
   - Update AUR packages on release

2. Use tools like:
   - `aurutils` for local AUR builds
   - `nfpm` for easy PKGBUILD generation

## AUR Best Practices

1. **Keep PKGBUILDs simple** - Only include what's necessary
2. **Use upstream versions** - Don't modify version numbers unnecessarily
3. **Comment changes** - Add helpful comments in PKGBUILD
4. **Test thoroughly** - Always test on clean Arch install
5. **Document dependencies** - Be precise about optdepends
6. **Follow Arch standards** - Use standard directories (/usr/local/bin, etc)
7. **License compliance** - Always include LICENSE file

## Package Naming Conventions

- Lowercase with hyphens: `selahos-device-editors`
- Prefix with `selahos-` for consistency
- Use full package name, not abbreviations

## File Organization

```
AUR/
├── selahos-device-editors/
│   ├── PKGBUILD
│   └── .SRCINFO  (generated)
├── selahos-device-bridge-web/
│   ├── PKGBUILD
│   └── .SRCINFO
├── selahos-device-scripting/
│   ├── PKGBUILD
│   └── .SRCINFO
└── SUBMISSION_GUIDE.md
```

## Submission Timeline

1. **Week 1**: Submit selahos-device-editors
2. **Week 2**: Submit selahos-device-bridge-web
3. **Week 3**: Submit selahos-device-scripting

## Support & Questions

For AUR questions:
- AUR Wiki: https://wiki.archlinux.org/title/Arch_User_Repository
- AUR Discussion Forum: https://bbs.archlinux.org/
- AUR Mailing List: aur-general@archlinux.org

For SelahOS:
- GitHub: https://github.com/SelahOS/selahos-iso/issues
- Email: support@selahtechnologies.com

## Maintenance Requirements

Once published on AUR:

- **Monitor for failures** - AUR bots may report build issues
- **Keep updated** - Update packages when new versions released
- **Fix security issues** - Immediately if dependencies are vulnerable
- **Respond to comments** - AUR maintainers/users may have suggestions
- **Maintain .SRCINFO** - Always keep synchronized with PKGBUILD

## Success Indicators

Package successfully submitted when:
- ✓ Repository appears on https://aur.archlinux.org/packages
- ✓ Clone URL works: `git clone https://aur.archlinux.org/selahos-device-editors.git`
- ✓ Users can install: `yay -S selahos-device-editors`
- ✓ Package builds without warnings
- ✓ Functionality matches local build
