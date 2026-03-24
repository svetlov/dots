#Requires AutoHotkey v2.0

; ─── Single key remaps ───
CapsLock::Esc

; ─── Backspace combos ───
<+Backspace::Delete                ; LShift+Backspace → Delete
>+Backspace::Send "{CapsLock}"     ; RShift+Backspace → CapsLock
^Backspace::Delete                 ; Ctrl+Backspace → Delete

; ─── Alt → Ctrl shortcuts (macOS-like) ───
<!a::^a                            ; select all
<!c::^c                            ; copy
<!f::^f                            ; find
<!q::!F4                           ; quit window
<!r::^r                            ; refresh
<!v::^v                            ; paste
<!x::^x                            ; cut
<!z::^z                            ; undo
<!+z::^+z                          ; redo

; ─── ISO key left of Z (SC056) ───
<+SC056::SendText "~"              ; LShift+ISO → tilde
<+Esc::SendText "``"               ; LShift+Esc → backtick
