;--------------------------------------------------------------------- ; Enhanced 16-bit fixed-point ball dynamics for PIC12F675 ; Using Q8.8 fixed-point: high byte = screen coordinate, low byte = sub-pixel ;---------------------------------------------------------------------

; New register allocations (bank 0): X_POS_L     EQU 022H   ; low byte of ball X (fixed-point) X_POS_H     EQU 022+1  ; high byte of ball X (screen X) Y_POS_L     EQU 023H   ; low byte of ball Y (fixed-point) Y_POS_H     EQU 023+1  ; high byte of ball Y (screen Y) VEL_X_L     EQU 036H   ; low byte of X velocity VEL_X_H     EQU 036+1  ; high byte of X velocity (signed Q8.8) VEL_Y_L     EQU 038H   ; low byte of Y velocity VEL_Y_H     EQU 038+1  ; high byte of Y velocity

; Initialize velocity in init sequence: ; Example: 1.5 pixels/frame to the right => VEL_X_H:VEL_X_L = 0x0100 + 0x0080 movlw   01H movwf   VEL_X_H      ; +1 pixel movlw   080H movwf   VEL_X_L      ; +0.5 pixel movlw   00H movwf   VEL_Y_H      ; no vertical motion movlw   00H movwf   VEL_Y_L

; Override ball_inv to reset 16-bit position ball_inv: ; Place off-screen: X = -8, Y = -8 (signed) => Q8.8 = 0xF800 movlw   0F8H movwf   X_POS_H clrf    X_POS_L movlw   0F8H movwf   Y_POS_H clrf    Y_POS_L return

; Updated x_move routine (16-bit add with sub-pixel) x_move: decfsz  X_SPEED,1    ; frame counter goto    x_move_idle movf    SPEED,0 movwf   X_SPEED ; accumulate: (X_POS_L:X_POS_H) += (VEL_X_L:VEL_X_H) movf    VEL_X_L, W addwf   X_POS_L, F movf    VEL_X_H, W addwfc  X_POS_H, F

; Extract screen X: top byte = X_POS_H
movf    X_POS_H, W
movwf   X_BALL
; Check collision or bounds
btfss   BITS_1, L2R  ; direction flag
goto    x_move_done
; when moving right-to-left, similar but flip sign if needed
; Collision and bounds logic remains unchanged but use X_BALL

x_move_done: return x_move_idle: nop goto    x_move_done

; Updated y_move routine (16-bit fixed-point) y_move: decfsz  Y_SPEED,1 goto    y_move_idle movf    SPEED

