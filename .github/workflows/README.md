# SelahOS CI/CD Pipeline

Automated testing, building, and release process for SelahOS Device Editors.

## Workflows

### Test Device Editors (`test-device-editors.yml`)

Triggered on:
- Push to `main` (if device editor files changed)
- Pull requests to `main` (if device editor files changed)

Tests performed:
- **Python Tests**: Syntax validation, linting, unit tests
- **Frontend Tests**: Vue.js build validation, bundle size
- **Syntax Check**: Python compilation, JSON validation
- **Integration Tests**: Module imports, API compilation
- **Documentation Check**: README files present

Matrix testing:
- Python 3.8, 3.9, 3.10, 3.11
- Node.js 18

### Build Release (`build-release.yml`)

Triggered on:
- Git tags matching `v*` (e.g., `v1.0.0`)
- Manual workflow dispatch

Builds:
- Device editors package
- Web interface (Vue.js)
- Scripting module (Python)
- Checksums for all packages

Artifacts:
- `device-editors-vX.Y.Z.tar.gz`
- `device-editors-web-vX.Y.Z.tar.gz`
- `device-scripting-vX.Y.Z.tar.gz`
- `CHECKSUMS` file

## Local Build

Build packages locally with:

```bash
./tools/build-device-editors.sh 1.0.0 ./dist/
```

This creates:
- `dist/device-editors-1.0.0.tar.gz`
- `dist/device-scripting-1.0.0.tar.gz`
- `dist/CHECKSUMS-1.0.0`
- `dist/MANIFEST-1.0.0.txt`

## Release Process

1. **Create tag**:
   ```bash
   git tag -a v1.0.0 -m "Release 1.0.0"
   git push origin v1.0.0
   ```

2. **GitHub Actions builds packages** (automated)

3. **Artifacts uploaded to release** (automated)

4. **Verify checksums**:
   ```bash
   sha256sum -c CHECKSUMS
   ```

5. **Publish release** (manual, via GitHub UI)

## Test Coverage

### Device Editors
- [x] All editors load without errors
- [x] Syntax validation (py_compile)
- [x] Linting (flake8)
- [x] Import verification

### Web Interface
- [x] Vue.js compilation
- [x] Build bundle validation
- [x] No compilation warnings

### Scripting Module
- [x] Macro creation
- [x] Executor initialization
- [x] Library management
- [x] JSON import/export

### Integration
- [x] Frontend + Backend API
- [x] Module cross-imports
- [x] Configuration loading

## Status Badges

Add to README:

```markdown
[![CI](https://github.com/SelahOS/selahos-iso/workflows/Test%20Device%20Editors/badge.svg)](https://github.com/SelahOS/selahos-iso/actions)
[![Release](https://github.com/SelahOS/selahos-iso/workflows/Build%20Release/badge.svg)](https://github.com/SelahOS/selahos-iso/actions)
```

## Performance

- **Test run time**: ~2-3 minutes
- **Build run time**: ~5-10 minutes
- **Release build**: ~10-15 minutes

## Failure Handling

If tests fail:
1. Check GitHub Actions logs for details
2. Run failing test locally: `python -m pytest tools/device-editors-web/scripting/`
3. Fix issues and push
4. CI/CD re-runs automatically

## Future Enhancements

- [ ] Deploy web interface to GitHub Pages
- [ ] Automatic Docker image builds
- [ ] Publish to PyPI (scripting module)
- [ ] AUR package auto-submission
- [ ] Performance benchmarking
- [ ] Code coverage reporting
- [ ] Security scanning (SAST)

## Secrets & Authentication

No secrets required for public releases.

For future auto-deployment:
- `GITHUB_TOKEN` (built-in)
- `PYPI_TOKEN` (if publishing to PyPI)
- `AUR_KEY` (if auto-submitting to AUR)

## Matrix Combinations

Python test matrix:
- Python 3.8 (legacy support)
- Python 3.9 (stable)
- Python 3.10 (current)
- Python 3.11 (latest)

Total test combinations: 4 × (Python tests + all jobs) = ~24 test runs per push

## Troubleshooting

### "Node modules not found"
- Frontend dependencies not cached
- Solution: Run `npm install` locally before pushing

### "Python version mismatch"
- Ensure code works with specified Python versions
- Solution: Test with `python3.8`, `python3.10`, etc. locally

### "Build artifact not found"
- Previous build step failed
- Solution: Check upstream job logs in Actions tab

## Contact

For CI/CD issues:
- Check `.github/workflows/*.yml` syntax
- Open issue on GitHub with workflow logs
- Reference: https://docs.github.com/en/actions
