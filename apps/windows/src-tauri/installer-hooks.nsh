; The app's own cleanup before its files go: hooks, skill and MCP entry written by
; `cots setup`, and the install folder on the user's PATH. Same as Ajustes → Desinstalar.
!macro NSIS_HOOK_PREUNINSTALL
  nsExec::Exec '"$INSTDIR\coTsApp.exe" --uninstall'
!macroend
