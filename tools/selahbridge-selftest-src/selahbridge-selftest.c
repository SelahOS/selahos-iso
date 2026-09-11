/*
 * selahbridge-selftest.c
 *
 * Minimal, self-contained "Windows audio app" used to verify SelahBridgePro
 * end-to-end: can it install (copy to Program Files, write a registry
 * uninstall key -- the two things every real installer does) and can the
 * resulting app actually reach Windows audio (waveOutOpen / PlaySound)
 * under Wine. Deliberately not a third-party binary: no licensing
 * question, no download/mirror dependency (see the 2026-08-17 wine-staging
 * pacstrap mirror failure this project hit -- adding another network
 * dependency to fix a network-fragility bug would be self-defeating).
 *
 * Usage: selahbridge-selftest.exe [/S]
 *   /S  - silent (no message box), used by selah-bridgepro-selftest
 *
 * Writes results to <installdir>\selftest-result.txt as KEY=OK/FAIL lines
 * so the host-side bash checker can parse it without needing to talk to
 * Wine directly.
 */
#include <windows.h>
#include <mmsystem.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    int silent = 0;
    for (int i = 1; i < argc; i++) {
        if (_stricmp(argv[i], "/S") == 0 || _stricmp(argv[i], "-S") == 0) {
            silent = 1;
        }
    }

    char installDir[MAX_PATH];
    DWORD n = GetEnvironmentVariableA("ProgramFiles", installDir, MAX_PATH - 32);
    if (n == 0 || n > MAX_PATH - 32) {
        strcpy(installDir, "C:\\Program Files");
    }
    strcat(installDir, "\\SelahBridgeProSelfTest");
    CreateDirectoryA(installDir, NULL);

    char exePath[MAX_PATH];
    GetModuleFileNameA(NULL, exePath, MAX_PATH);
    char destPath[MAX_PATH];
    snprintf(destPath, MAX_PATH, "%s\\selftest.exe", installDir);
    BOOL copyOk = CopyFileA(exePath, destPath, FALSE);

    /* Typical installer behavior: register an uninstall entry. */
    HKEY hKey;
    LONG regOk = RegCreateKeyExA(
        HKEY_LOCAL_MACHINE,
        "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\SelahBridgeProSelfTest",
        0, NULL, 0, KEY_WRITE, NULL, &hKey, NULL);
    if (regOk == ERROR_SUCCESS) {
        const char *name = "SelahBridgePro Self-Test";
        RegSetValueExA(hKey, "DisplayName", 0, REG_SZ,
                        (const BYTE *)name, (DWORD)strlen(name) + 1);
        RegCloseKey(hKey);
    }

    /* The actual "audio app" part: can we reach Windows audio at all. */
    int waveOk = 0;
    WAVEFORMATEX wfx;
    memset(&wfx, 0, sizeof(wfx));
    wfx.wFormatTag = WAVE_FORMAT_PCM;
    wfx.nChannels = 2;
    wfx.nSamplesPerSec = 44100;
    wfx.wBitsPerSample = 16;
    wfx.nBlockAlign = (WORD)(wfx.nChannels * wfx.wBitsPerSample / 8);
    wfx.nAvgBytesPerSec = wfx.nSamplesPerSec * wfx.nBlockAlign;

    HWAVEOUT hWave;
    if (waveOutOpen(&hWave, WAVE_MAPPER, &wfx, 0, 0, CALLBACK_NULL) == MMSYSERR_NOERROR) {
        waveOk = 1;
        waveOutClose(hWave);
    }

    int playSoundOk = PlaySoundA("SystemAsterisk", NULL,
                                  SND_ALIAS | SND_SYNC | SND_NODEFAULT) ? 1 : 0;

    char logPath[MAX_PATH];
    snprintf(logPath, MAX_PATH, "%s\\selftest-result.txt", installDir);
    FILE *f = fopen(logPath, "w");
    if (f) {
        fprintf(f, "INSTALL_COPY=%s\n", copyOk ? "OK" : "FAIL");
        fprintf(f, "REGISTRY_WRITE=%s\n", regOk == ERROR_SUCCESS ? "OK" : "FAIL");
        fprintf(f, "AUDIO_WAVEOUT=%s\n", waveOk ? "OK" : "FAIL");
        fprintf(f, "AUDIO_PLAYSOUND=%s\n", playSoundOk ? "OK" : "FAIL");
        fclose(f);
    }

    if (!silent) {
        MessageBoxA(NULL,
            waveOk ? "SelahBridgePro self-test complete: audio OK."
                   : "SelahBridgePro self-test complete: audio FAILED.",
            "SelahBridgePro Self-Test", MB_OK);
    }

    return (copyOk && waveOk) ? 0 : 1;
}
