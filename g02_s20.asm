# --- ĐỊA CHỈ MMIO KEYBOARD & DISPLAY SIMULATOR ---
.eqv KBD_CTRL           0xFFFF0000  # Địa chỉ thanh ghi điều khiển bàn phím
.eqv KBD_DATA           0xFFFF0004  # Địa chỉ thanh ghi dữ liệu bàn phím
.eqv DSP_CTRL           0xFFFF0008  # Địa chỉ thanh ghi điều khiển màn hình text
.eqv DSP_DATA           0xFFFF000C  # Địa chỉ thanh ghi dữ liệu màn hình text

# --- ĐỊA CHỈ & THÔNG SỐ BITMAP DISPLAY ---
.eqv BITMAP_BASE        0x10010000  # Địa chỉ gốc của màn hình đồ họa (Bitmap)
.eqv DISPLAY_WIDTH      256         # Chiều rộng màn hình (256 pixel)
.eqv DISPLAY_HEIGHT     256         # Chiều cao màn hình (256 pixel)

# --- MÃ MÀU SẮC ---
.eqv COLOR_BLUE         0xFF0000FF  # Mã màu Xanh dương (định dạng ARGB)
.eqv COLOR_YELLOW       0xFFFFFF00  # Mã màu Vàng
.eqv COLOR_RED          0xFFFF0000  # Mã màu Đỏ
.eqv COLOR_GREEN        0xFF00FF00  # Mã màu Xanh lá

.data
    cmd_buffer:  .space 64          # Bộ đệm lưu trữ chuỗi lệnh (tối đa 64 ký tự)
    fill_stack:  .space 524288      # Vùng nhớ stack phục vụ thuật toán tô màu
    current_color: .word -1         # Màu mặc định ban đầu của hệ thống
    
    # Chuỗi phản hồi hiển thị trên Display MMIO
    msg_valid:   .asciz "Lenh dung!\n"   # Thông báo khi lệnh đúng cú pháp
    msg_invalid: .asciz "Sai cu phap!\n" # Thông báo khi lệnh sai cú pháp

.text
main:
    la s0, cmd_buffer               # s0 = Con trỏ ghi vào bộ đệm
    li s1, 0                        # s1 = Biến đếm số ký tự đã nhập

kbd_loop:
    # 1. Chờ người dùng nhấn phím trên Keyboard MMIO
    li t5, KBD_CTRL                 # Tải địa chỉ điều khiển bàn phím vào t5
    lw t6, 0(t5)                    # Đọc giá trị từ thanh ghi điều khiển vào t6
    andi t6, t6, 1                  # Trích xuất bit Ready (bit cuối cùng)
    beqz t6, kbd_loop               # Nếu bit ready == 0, tiếp tục đợi
    
    # 2. Đọc ký tự từ bộ đệm bàn phím
    li t5, KBD_DATA                 # Tải địa chỉ dữ liệu bàn phím vào t5
    lb a0, 0(t5)                    # a0 = Ký tự vừa nhập (đọc 1 byte)
    
    # 3. Echo (In lại) ký tự vừa gõ lên Display MMIO để người dùng thấy thanh lệnh
    jal print_char_mmio             # Gọi hàm xuất ký tự trong a0 ra màn hình text
    
    # 4. Kiểm tra nút Enter (Ký tự '\n' mã ASCII = 10 hoặc '\r' = 13)
    li t2, 10                       # t2 = mã ASCII của '\n'
    beq a0, t2, handle_enter        # Nếu là Enter, nhảy đến xử lý lệnh
    li t2, 13                       # t2 = mã ASCII của '\r'
    beq a0, t2, handle_enter        # Nếu là Enter (CR), nhảy đến xử lý lệnh
    
    # Kiểm tra tràn bộ đệm lệnh (giới hạn 60 ký tự)
    li t2, 60                       # t2 = ngưỡng giới hạn bộ đệm (60 ký tự)
    bge s1, t2, kbd_loop            # Nếu đã đạt giới hạn, bỏ qua không lưu ký tự này
    
    # 5. Lưu ký tự vào bộ đệm chuỗi
    sb a0, 0(s0)                    # Lưu ký tự trong a0 vào vị trí hiện tại của bộ đệm
    addi s0, s0, 1                  # Tiến con trỏ bộ đệm lên 1 byte
    addi s1, s1, 1                  # Tăng đếm ký tự lên 1
    j kbd_loop                      # Quay lại vòng lặp chờ phím tiếp theo

handle_enter:
    sb zero, 0(s0)                  # Thêm ký tự Null (\0) để kết thúc chuỗi
    
    # Tiến hành phân tích cú pháp lệnh đã nhập
    jal parse_command               # Gọi hàm xử lý và thực thi lệnh
    
reset_buffer:
    # Reset lại bộ đệm chuẩn bị cho lệnh tiếp theo
    la s0, cmd_buffer               # Đặt lại con trỏ s0 về đầu bộ đệm
    li s1, 0                        # Đặt lại số ký tự đếm được về 0
    j kbd_loop                      # Quay lại vòng lặp nhận phím mới
    
# =================================================================
# HÀM PHÂN TÍCH CÚ PHÁP LỆNH (Command Parser)
# =================================================================
parse_command:
    addi sp, sp, -24                # Lưu trữ các thanh ghi vào Stack
    sw ra, 0(sp)                    # Lưu địa chỉ trả về (return address)
    sw s5, 4(sp)                    # Lưu thanh ghi s5
    sw s6, 8(sp)                    # Lưu thanh ghi s6
    sw s7, 12(sp)                   # Lưu thanh ghi s7
    sw s8, 16(sp)                   # Lưu thanh ghi s8

    la t0, cmd_buffer               # t0 = Địa chỉ bắt đầu của bộ đệm lệnh
    
    # --- KIỂM TRA LỆNH "color " (6 ký tự) ---
    lb t1, 0(t0)                    # Đọc ký tự thứ 1 (vị trí 0)
    li t2, 'c'                      # Mã ASCII của ký tự 'c'
    bne t1, t2, check_line          # Nếu không phải 'c', nhảy sang kiểm tra lệnh vẽ đường thẳng
    lb t1, 1(t0)                    # Đọc ký tự thứ 2 (vị trí 1)
    li t2, 'o'                      # Mã ASCII của ký tự 'o'
    bne t1, t2, check_circle        # Nếu không phải 'o', nhảy sang kiểm tra lệnh vẽ đường tròn
    lb t1, 2(t0)                    # Đọc ký tự thứ 3 (vị trí 2)
    li t2, 'l'                      # Mã ASCII của ký tự 'l'
    bne t1, t2, cmd_error           # Nếu không phải 'l', báo lỗi cú pháp
    lb t1, 3(t0)                    # Đọc ký tự thứ 4 (vị trí 3)
    li t2, 'o'                      # Mã ASCII của ký tự 'o'
    bne t1, t2, cmd_error           # Nếu không phải 'o', báo lỗi cú pháp
    lb t1, 4(t0)                    # Đọc ký tự thứ 5 (vị trí 4)
    li t2, 'r'                      # Mã ASCII của ký tự 'r'
    bne t1, t2, cmd_error           # Nếu không phải 'r', báo lỗi cú pháp
    lb t1, 5(t0)                    # Đọc ký tự thứ 6 (vị trí 5)
    li t2, ' '                      # Mã ASCII của ký tự khoảng trắng ' '
    bne t1, t2, cmd_error           # Nếu không phải khoảng trắng, báo lỗi cú pháp
    
    # Cú pháp đúng, trích xuất mã màu n
    addi a0, t0, 6                  # a0 = Địa chỉ chuỗi số (bỏ qua 6 ký tự "color ")
    jal atoi                        # Chuyển đổi tham số thứ 1 sang số nguyên
    bnez a2, cmd_error              # Nếu lỗi định dạng số (a2 != 0), báo sai cú pháp
    
    # Lựa chọn màu dựa trên n (0: Blue, 1: Yellow, 2: Red, 3: Green)
    li t1, 0                        # t1 = 0
    beq a0, t1, set_blue            # Nếu n == 0, nhảy đến cài đặt màu Blue

    li t1, 1                        # t1 = 1
    beq a0, t1, set_yellow          # Nếu n == 1, nhảy đến cài đặt màu Yellow

    li t1, 2                        # t1 = 2
    beq a0, t1, set_red             # Nếu n == 2, nhảy đến cài đặt màu Red
    
    li t1, 3                        # t1 = 3
    beq a0, t1, set_green           # Nếu n == 3, nhảy đến cài đặt màu Green

    # Không phải 0,1,2,3 => lỗi
    j cmd_error                     # Nhảy đến xử lý lỗi nếu n không hợp lệ

set_blue:
    li t2, COLOR_BLUE               # t2 = Mã màu Xanh dương
    la t3, current_color            # t3 = Địa chỉ biến màu hiện tại
    sw t2, 0(t3)                    # Cập nhật màu mới vào current_color
    j cmd_success                   # Nhảy đến xử lý thành công

set_yellow:
    li t2, COLOR_YELLOW             # t2 = Mã màu Vàng
    la t3, current_color            # t3 = Địa chỉ biến màu hiện tại
    sw t2, 0(t3)                    # Cập nhật màu mới vào current_color
    j cmd_success                   # Nhảy đến xử lý thành công

set_red:
    li t2, COLOR_RED                # t2 = Mã màu Đỏ
    la t3, current_color            # t3 = Địa chỉ biến màu hiện tại
    sw t2, 0(t3)                    # Cập nhật màu mới vào current_color
    j cmd_success                   # Nhảy đến xử lý thành công

set_green:
    li t2, COLOR_GREEN              # t2 = Mã màu Xanh lá
    la t3, current_color            # t3 = Địa chỉ biến màu hiện tại
    sw t2, 0(t3)                    # Cập nhật màu mới vào current_color
    j cmd_success                   # Nhảy đến xử lý thành công

check_line:
    # --- KIỂM TRA LỆNH "line " (5 ký tự) ---
    lb t1, 0(t0)                    # Đọc ký tự thứ 1 (vị trí 0)
    li t2, 'l'                      # Mã ASCII của ký tự 'l'
    bne t1, t2, check_rectangle     # Nếu không phải 'l', nhảy sang kiểm tra lệnh vẽ hình chữ nhật
    lb t1, 1(t0)                    # Đọc ký tự thứ 2 (vị trí 1)
    li t2, 'i'                      # Mã ASCII của ký tự 'i'
    bne t1, t2, cmd_error           # Nếu không phải 'i', báo lỗi cú pháp
    lb t1, 2(t0)                    # Đọc ký tự thứ 3 (vị trí 2)
    li t2, 'n'                      # Mã ASCII của ký tự 'n'
    bne t1, t2, cmd_error           # Nếu không phải 'n', báo lỗi cú pháp
    lb t1, 3(t0)                    # Đọc ký tự thứ 4 (vị trí 3)
    li t2, 'e'                      # Mã ASCII của ký tự 'e'
    bne t1, t2, cmd_error           # Nếu không phải 'e', báo lỗi cú pháp
    lb t1, 4(t0)                    # Đọc ký tự thứ 5 (vị trí 4)
    li t2, ' '                      # Mã ASCII của ký tự khoảng trắng ' '
    bne t1, t2, cmd_error           # Nếu không phải khoảng trắng, báo lỗi cú pháp
    
    # Trích xuất 4 tham số: x1, y1, x2, y2
    addi a0, t0, 5                  # a0 = Địa chỉ bắt đầu tham số (bỏ qua 5 ký tự "line ")
    jal atoi                        # Chuyển đổi chuỗi sang số nguyên để đọc x1
    bnez a2, cmd_error              # Nếu lỗi định dạng, báo sai cú pháp
    mv s5, a0                       # s5 = x1
    
    mv a0, a1                       # a0 = Địa chỉ của tham số tiếp theo (do hàm atoi trả về ở a1)
    jal atoi                        # Chuyển đổi chuỗi sang số nguyên để đọc y1
    bnez a2, cmd_error              # Nếu lỗi định dạng, báo sai cú pháp
    mv s6, a0                       # s6 = y1
    
    mv a0, a1                       # a0 = Địa chỉ của tham số tiếp theo
    jal atoi                        # Chuyển đổi chuỗi sang số nguyên để đọc x2
    bnez a2, cmd_error              # Nếu lỗi định dạng, báo sai cú pháp
    mv s7, a0                       # s7 = x2
    
    mv a0, a1                       # a0 = Địa chỉ của tham số tiếp theo
    jal atoi                        # Chuyển đổi chuỗi sang số nguyên để đọc y2
    bnez a2, cmd_error              # Nếu lỗi định dạng, báo sai cú pháp
    mv s8, a0                       # s8 = y2
    
    # Thực hiện vẽ đường thẳng lên màn hình Bitmap
    mv a0, s5                       # Tham số 1: x1
    mv a1, s6                       # Tham số 2: y1
    mv a2, s7                       # Tham số 3: x2
    mv a3, s8                       # Tham số 4: y2
    la t1, current_color            # t1 = Địa chỉ biến màu hiện tại
    lw a4, 0(t1)                    # Nạp màu hiện tại vào thanh ghi tham số a4
    jal draw_line                   # Gọi hàm vẽ đường thẳng
    j cmd_success                   # Nhảy đến xử lý thành công

check_rectangle:
    # --- KIEM TRA LENH "rectangle " (10 ky tu) ---
    lb t1, 0(t0)                    # Đọc ký tự thứ 1 (vị trí 0)
    li t2, 'r'                      # Mã ASCII của ký tự 'r'
    bne t1, t2, check_fill          # Nếu không phải 'r', nhảy sang kiểm tra lệnh tô màu (fill)

    lb t1, 1(t0)                    # Đọc ký tự thứ 2 (vị trí 1)
    li t2, 'e'                      # Mã ASCII của ký tự 'e'
    bne t1, t2, cmd_error           # Nếu không phải 'e', báo lỗi cú pháp

    lb t1, 2(t0)                    # Đọc ký tự thứ 3 (vị trí 2)
    li t2, 'c'                      # Mã ASCII của ký tự 'c'
    bne t1, t2, cmd_error           # Nếu không phải 'c', báo lỗi cú pháp

    lb t1, 3(t0)                    # Đọc ký tự thứ 4 (vị trí 3)
    li t2, 't'                      # Mã ASCII của ký tự 't'
    bne t1, t2, cmd_error           # Nếu không phải 't', báo lỗi cú pháp

    lb t1, 4(t0)                    # Đọc ký tự thứ 5 (vị trí 4)
    li t2, 'a'                      # Mã ASCII của ký tự 'a'
    bne t1, t2, cmd_error           # Nếu không phải 'a', báo lỗi cú pháp

    lb t1, 5(t0)                    # Đọc ký tự thứ 6 (vị trí 5)
    li t2, 'n'                      # Mã ASCII của ký tự 'n'
    bne t1, t2, cmd_error           # Nếu không phải 'n', báo lỗi cú pháp

    lb t1, 6(t0)                    # Đọc ký tự thứ 7 (vị trí 6)
    li t2, 'g'                      # Mã ASCII của ký tự 'g'
    bne t1, t2, cmd_error           # Nếu không phải 'g', báo lỗi cú pháp

    lb t1, 7(t0)                    # Đọc ký tự thứ 8 (vị trí 7)
    li t2, 'l'                      # Mã ASCII của ký tự 'l'
    bne t1, t2, cmd_error           # Nếu không phải 'l', báo lỗi cú pháp

    lb t1, 8(t0)                    # Đọc ký tự thứ 9 (vị trí 8)
    li t2, 'e'                      # Mã ASCII của ký tự 'e'
    bne t1, t2, cmd_error           # Nếu không phải 'e', báo lỗi cú pháp

    lb t1, 9(t0)                    # Đọc ký tự thứ 10 (vị trí 9)
    li t2, ' '                      # Mã ASCII của ký tự khoảng trắng ' '
    bne t1, t2, cmd_error           # Nếu không phải khoảng trắng, báo lỗi cú pháp

    # Doc x1
    addi a0, t0, 10                 # a0 = Địa chỉ bắt đầu tham số (bỏ qua 10 ký tự "rectangle ")
    jal atoi                        # Chuyển đổi chuỗi sang số nguyên để đọc x1
    bnez a2, cmd_error              # Nếu lỗi định dạng, báo sai cú pháp
    mv s5, a0                       # s5 = x1

    # Doc y1
    mv a0, a1                       # a0 = Địa chỉ của tham số tiếp theo
    jal atoi                        # Chuyển đổi chuỗi sang số nguyên để đọc y1
    bnez a2, cmd_error              # Nếu lỗi định dạng, báo sai cú pháp
    mv s6, a0                       # s6 = y1

    # Doc x2
    mv a0, a1                       # a0 = Địa chỉ của tham số tiếp theo
    jal atoi                        # Chuyển đổi chuỗi sang số nguyên để đọc x2
    bnez a2, cmd_error              # Nếu lỗi định dạng, báo sai cú pháp
    mv s7, a0                       # s7 = x2

    # Doc y2
    mv a0, a1                       # a0 = Địa chỉ của tham số tiếp theo
    jal atoi                        # Chuyển đổi chuỗi sang số nguyên để đọc y2
    bnez a2, cmd_error              # Nếu lỗi định dạng, báo sai cú pháp
    mv s8, a0                       # s8 = y2

    # Goi ham ve hinh chu nhat
    mv a0, s5                       # Tham số 1: x1
    mv a1, s6                       # Tham số 2: y1
    mv a2, s7                       # Tham số 3: x2
    mv a3, s8                       # Tham số 4: y2

    la t1, current_color            # t1 = Địa chỉ biến màu hiện tại
    lw a4, 0(t1)                    # Nạp màu hiện tại vào thanh ghi tham số a4

    jal draw_rectangle              # Gọi hàm vẽ hình chữ nhật

    j cmd_success                   # Nhảy đến xử lý thành công
    
check_circle:
    # --- KIEM TRA LENH "circle " (7 ky tu) ---
    lb t1, 0(t0)                    # Đọc ký tự thứ 1 (vị trí 0)
    li t2, 'c'                      # Mã ASCII của ký tự 'c'
    bne t1, t2, cmd_error           # Nếu không phải 'c', báo lỗi cú pháp

    lb t1, 1(t0)                    # Đọc ký tự thứ 2 (vị trí 1)
    li t2, 'i'                      # Mã ASCII của ký tự 'i'
    bne t1, t2, cmd_error           # Nếu không phải 'i', báo lỗi cú pháp

    lb t1, 2(t0)                    # Đọc ký tự thứ 3 (vị trí 2)
    li t2, 'r'                      # Mã ASCII của ký tự 'r'
    bne t1, t2, cmd_error           # Nếu không phải 'r', báo lỗi cú pháp

    lb t1, 3(t0)                    # Đọc ký tự thứ 4 (vị trí 3)
    li t2, 'c'                      # Mã ASCII của ký tự 'c'
    bne t1, t2, cmd_error           # Nếu không phải 'c', báo lỗi cú pháp

    lb t1, 4(t0)                    # Đọc ký tự thứ 5 (vị trí 4)
    li t2, 'l'                      # Mã ASCII của ký tự 'l'
    bne t1, t2, cmd_error           # Nếu không phải 'l', báo lỗi cú pháp

    lb t1, 5(t0)                    # Đọc ký tự thứ 6 (vị trí 5)
    li t2, 'e'                      # Mã ASCII của ký tự 'e'
    bne t1, t2, cmd_error           # Nếu không phải 'e', báo lỗi cú pháp

    lb t1, 6(t0)                    # Đọc ký tự thứ 7 (vị trí 6)
    li t2, ' '                      # Mã ASCII của ký tự khoảng trắng ' '
    bne t1, t2, cmd_error           # Nếu không phải khoảng trắng, báo lỗi cú pháp

    # Doc x
    addi a0, t0, 7                  # a0 = Địa chỉ bắt đầu tham số (bỏ qua 7 ký tự "circle ")
    jal atoi                        # Chuyển đổi chuỗi sang số nguyên để đọc tâm x
    bnez a2, cmd_error              # Nếu lỗi định dạng, báo sai cú pháp
    mv s5, a0                       # s5 = x

    # Doc y
    mv a0, a1                       # a0 = Địa chỉ của tham số tiếp theo (do hàm atoi trả về ở a1)
    jal atoi                        # Chuyển đổi chuỗi sang số nguyên để đọc tâm y
    bnez a2, cmd_error              # Nếu lỗi định dạng, báo sai cú pháp
    mv s6, a0                       # s6 = y

    # Doc r
    mv a0, a1                       # a0 = Địa chỉ của tham số tiếp theo
    jal atoi                        # Chuyển đổi chuỗi sang số nguyên để đọc bán kính r
    bnez a2, cmd_error              # Nếu lỗi định dạng, báo sai cú pháp
    mv s7, a0                       # s7 = r

    # Chuẩn bị tham số gọi hàm vẽ hình tròn
    mv a0, s5                       # Tham số 1: tâm x
    mv a1, s6                       # Tham số 2: tâm y
    mv a2, s7                       # Tham số 3: bán kính r

    la t1, current_color            # t1 = Địa chỉ biến màu hiện tại
    lw a3, 0(t1)                    # Nạp màu hiện tại vào thanh ghi tham số a3

    jal draw_circle                 # Gọi hàm vẽ đường tròn

    j cmd_success                   # Nhảy đến xử lý thành công

check_fill:
    # --- KIEM TRA LENH "fill " (5 ky tu) ---
    lb t1, 0(t0)                    # Đọc ký tự thứ 1 (vị trí 0)
    li t2, 'f'                      # Mã ASCII của ký tự 'f'
    bne t1, t2, cmd_error           # Nếu không phải 'f', báo lỗi cú pháp

    lb t1, 1(t0)                    # Đọc ký tự thứ 2 (vị trí 1)
    li t2, 'i'                      # Mã ASCII của ký tự 'i'
    bne t1, t2, cmd_error           # Nếu không phải 'i', báo lỗi cú pháp

    lb t1, 2(t0)                    # Đọc ký tự thứ 3 (vị trí 2)
    li t2, 'l'                      # Mã ASCII của ký tự 'l'
    bne t1, t2, cmd_error           # Nếu không phải 'l', báo lỗi cú pháp

    lb t1, 3(t0)                    # Đọc ký tự thứ 4 (vị trí 3)
    li t2, 'l'                      # Mã ASCII của ký tự 'l'
    bne t1, t2, cmd_error           # Nếu không phải 'l', báo lỗi cú pháp

    lb t1, 4(t0)                    # Đọc ký tự thứ 5 (vị trí 4)
    li t2, ' '                      # Mã ASCII của ký tự khoảng trắng ' '
    bne t1, t2, cmd_error           # Nếu không phải khoảng trắng, báo lỗi cú pháp

    # đọc x
    addi a0, t0, 5                  # a0 = Địa chỉ bắt đầu tham số (bỏ qua 5 ký tự "fill ")
    jal atoi                        # Chuyển đổi chuỗi sang số nguyên để đọc tọa độ điểm x
    bnez a2, cmd_error              # Nếu lỗi định dạng, báo sai cú pháp
    mv s5, a0                       # s5 = x

    # đọc y
    mv a0, a1                       # a0 = Địa chỉ của tham số tiếp theo
    jal atoi                        # Chuyển đổi chuỗi sang số nguyên để đọc tọa độ điểm y
    bnez a2, cmd_error              # Nếu lỗi định dạng, báo sai cú pháp
    mv s6, a0                       # s6 = y

    # Chuẩn bị tham số gọi hàm tô màu loang
    mv a0, s5                       # Tham số 1: tọa độ x bắt đầu tô
    mv a1, s6                       # Tham số 2: tọa độ y bắt đầu tô

    la t1, current_color            # t1 = Địa chỉ biến màu hiện tại
    lw a2, 0(t1)                    # Nạp màu hiện tại vào thanh ghi tham số a2

    jal flood_fill                  # Gọi hàm tô màu (Flood Fill)

    j cmd_success                   # Nhảy đến xử lý thành công
    
cmd_success:
    la a0, msg_valid                # a0 = Địa chỉ của chuỗi thông báo lệnh đúng ("Lenh dung!\n")
    jal print_str_mmio              # Gọi hàm in chuỗi thông báo lên màn hình text MMIO
    j parse_exit                    # Nhảy đến phần thoát hàm để khôi phục thanh ghi và trả về

cmd_error:
    la a0, msg_invalid              # a0 = Địa chỉ của chuỗi thông báo sai cú pháp ("Sai cu phap!\n")
    jal print_str_mmio              # Gọi hàm in chuỗi thông báo lỗi lên màn hình text MMIO

parse_exit:
    lw s8, 16(sp)                   # Khôi phục giá trị cũ của thanh ghi s8 từ Stack
    lw s7, 12(sp)                   # Khôi phục giá trị cũ của thanh ghi s7 từ Stack
    lw s6, 8(sp)                    # Khôi phục giá trị cũ của thanh ghi s6 từ Stack
    lw s5, 4(sp)                    # Khôi phục giá trị cũ của thanh ghi s5 từ Stack
    lw ra, 0(sp)                    # Khôi phục địa chỉ trả về (return address) ban đầu
    addi sp, sp, 24                 # Hoàn trả lại không gian vùng nhớ Stack (giải phóng 24 byte)
    ret                             # Quay trở về nơi gọi hàm parse_command

# =================================================================
# VẼ ĐƯỜNG THẲNG (Line Drawing)
# =================================================================
draw_line:
    # Tham số đầu vào: a0=x0, a1=y0, a2=x1, a3=y1, a4=color
    addi sp, sp, -24                # Lưu trữ các thanh ghi vào Stack để bảo toàn dữ liệu
    sw s0, 0(sp)                    # Lưu thanh ghi s0
    sw s1, 4(sp)                    # Lưu thanh ghi s1
    sw s2, 8(sp)                    # Lưu thanh ghi s2
    sw s3, 12(sp)                   # Lưu thanh ghi s3
    sw s4, 16(sp)                   # Lưu thanh ghi s4
    
    mv s0, a0                       # s0 = x0 (Tọa độ X điểm đầu)
    mv s1, a1                       # s1 = y0 (Tọa độ Y điểm đầu)
    mv s2, a2                       # s2 = x1 (Tọa độ X điểm cuối)
    mv s3, a3                       # s3 = y1 (Tọa độ Y điểm cuối)
    mv s4, a4                       # s4 = màu sắc cần vẽ

    # Tính dx = abs(x1 - x0)
    sub t0, s2, s0                  # t0 = x1 - x0
    li t2, 1                        # Mặc định hướng bước nhảy sx = 1 (vẽ từ trái sang phải)
    bgez t0, dx_ready               # Nếu dx >= 0, nhảy đến bước tiếp theo
    neg t0, t0                      # Nếu dx < 0, lấy giá trị tuyệt đối dx = -dx
    li t2, -1                       # Đổi hướng bước nhảy sx = -1 (vẽ từ phải sang trái)
dx_ready:

    # Tính dy = abs(y1 - y0)
    sub t1, s3, s1                  # t1 = y1 - y0
    li t3, 1                        # Mặc định hướng bước nhảy sy = 1 (vẽ từ trên xuống dưới)
    bgez t1, dy_ready               # Nếu dy >= 0, nhảy đến bước tiếp theo
    neg t1, t1                      # Nếu dy < 0, lấy giá trị tuyệt đối dy = -dy
    li t3, -1                       # Đổi hướng bước nhảy sy = -1 (vẽ từ dưới lên trên)
dy_ready:

    sub t4, t0, t1                  # t4 = err = dx - dy

loop_pixels:
    # Kiểm tra giới hạn màn hình bảo vệ bộ nhớ (0 <= x < 256, 0 <= y < 256)
    bltz s0, skip_pixel             # Nếu x0 < 0, bỏ qua không vẽ pixel này
    li t5, DISPLAY_WIDTH            # t5 = Chiều rộng màn hình
    bge s0, t5, skip_pixel          # Nếu x0 >= DISPLAY_WIDTH, bỏ qua không vẽ
    bltz s1, skip_pixel             # Nếu y0 < 0, bỏ qua không vẽ
    li t5, DISPLAY_HEIGHT           # t5 = Chiều cao màn hình
    bge s1, t5, skip_pixel          # Nếu y0 >= DISPLAY_HEIGHT, bỏ qua không vẽ

    # Tính toán địa chỉ ô nhớ pixel: Base + (y * 256 + x) * 4
    li t5, DISPLAY_WIDTH            # t5 = Chiều rộng màn hình
    mul t6, s1, t5                  # t6 = y0 * DISPLAY_WIDTH
    add t6, t6, s0                  # t6 = (y0 * DISPLAY_WIDTH) + x0
    slli t6, t6, 2                  # Nhân nhân 4 (dịch trái 2 bit) để đổi sang đơn vị byte
    li t5, BITMAP_BASE              # t5 = Địa chỉ gốc Bitmap Display
    add t6, t5, t6                  # t6 = Địa chỉ chính xác của pixel cần tô trên RAM
    sw s4, 0(t6)                    # Ghi mã màu từ s4 vào địa chỉ RAM để hiển thị pixel

skip_pixel:
    # Nếu đã vẽ tới điểm đích cuối cùng (x0==x1 && y0==y1) -> Thoát
    bne s0, s2, next_step           # Nếu x0 != x1, tiếp tục tính pixel tiếp theo
    beq s1, s3, end_draw            # Nếu x0 == x1 và y0 == y1, hoàn thành đường vẽ
    
next_step:
    slli t5, t4, 1                  # t5 = e2 = 2 * err
    
    neg t6, t1                      # t6 = -dy
    ble t5, t6, check_e2_dx         # Nếu e2 <= -dy, bỏ qua bước cập nhật X
    sub t4, t4, t1                  # Cập nhật biến lỗi: err -= dy
    add s0, s0, t2                  # Di chuyển tọa độ X: x0 += sx

check_e2_dx:
    bge t5, t0, loop_pixels         # Nếu e2 >= dx, quay lại vòng lặp vẽ pixel tiếp theo
    add t4, t4, t0                  # Cập nhật biến lỗi: err += dx
    add s1, s1, t3                  # Di chuyển tọa độ Y: y0 += sy
    j loop_pixels                   # Quay lại vòng lặp để vẽ pixel tiếp theo

end_draw:
    lw s4, 16(sp)                   # Khôi phục thanh ghi s4 từ Stack
    lw s3, 12(sp)                   # Khôi phục thanh ghi s3 từ Stack
    lw s2, 8(sp)                    # Khôi phục thanh ghi s2 từ Stack
    lw s1, 4(sp)                    # Khôi phục thanh ghi s1 từ Stack
    lw s0, 0(sp)                    # Khôi phục thanh ghi s0 từ Stack
    addi sp, sp, 24                 # Giải phóng vùng nhớ Stack
    ret                             # Quay trở về hàm gọi draw_line

# ==========================================================
# VE HINH CHU NHAT (RECTANGLE DRAWING)
# ==========================================================
draw_rectangle:
    addi sp, sp, -28                # Mở rộng vùng nhớ Stack để lưu các thanh ghi

    sw ra, 0(sp)                    # Lưu địa chỉ trả về (return address)
    sw s0, 4(sp)                    # Lưu thanh ghi s0
    sw s1, 8(sp)                    # Lưu thanh ghi s1
    sw s2, 12(sp)                   # Lưu thanh ghi s2
    sw s3, 16(sp)                   # Lưu thanh ghi s3
    sw s4, 20(sp)                   # Lưu thanh ghi s4

    mv s0, a0                       # s0 = x1 (Tọa độ X góc trên bên trái)
    mv s1, a1                       # s1 = y1 (Tọa độ Y góc trên bên trái)
    mv s2, a2                       # s2 = x2 (Tọa độ X góc dưới bên phải)
    mv s3, a3                       # s3 = y2 (Tọa độ Y góc dưới bên phải)
    mv s4, a4                       # s4 = color (Màu sắc của hình chữ nhật)

    # ------------------
    # Top edge (Cạnh trên: đi từ (x1, y1) đến (x2, y1))
    # ------------------
    mv a0, s0                       # Tham số 1: x1
    mv a1, s1                       # Tham số 2: y1
    mv a2, s2                       # Tham số 3: x2
    mv a3, s1                       # Tham số 4: y1
    mv a4, s4                       # Tham số 5: màu sắc
    jal draw_line                   # Gọi hàm vẽ cạnh trên hình chữ nhật

    # ------------------
    # Bottom edge (Cạnh dưới: đi từ (x1, y2) đến (x2, y2))
    # ------------------
    mv a0, s0                       # Tham số 1: x1
    mv a1, s3                       # Tham số 2: y2
    mv a2, s2                       # Tham số 3: x2
    mv a3, s3                       # Tham số 4: y2
    mv a4, s4                       # Tham số 5: màu sắc
    jal draw_line                   # Gọi hàm vẽ cạnh dưới hình chữ nhật

    # ------------------
    # Left edge (Cạnh bên trái: đi từ (x1, y1) đến (x1, y2))
    # ------------------
    mv a0, s0                       # Tham số 1: x1
    mv a1, s1                       # Tham số 2: y1
    mv a2, s0                       # Tham số 3: x1
    mv a3, s3                       # Tham số 4: y2
    mv a4, s4                       # Tham số 5: màu sắc
    jal draw_line                   # Gọi hàm vẽ cạnh bên trái hình chữ nhật

    # ------------------
    # Right edge (Cạnh bên phải: đi từ (x2, y1) đến (x2, y2))
    # ------------------
    mv a0, s2                       # Tham số 1: x2
    mv a1, s1                       # Tham số 2: y1
    mv a2, s2                       # Tham số 3: x2
    mv a3, s3                       # Tham số 4: y2
    mv a4, s4                       # Tham số 5: màu sắc
    jal draw_line                   # Gọi hàm vẽ cạnh bên phải hình chữ nhật

    lw s4, 20(sp)                   # Khôi phục thanh ghi s4 từ Stack
    lw s3, 16(sp)                   # Khôi phục thanh ghi s3 từ Stack
    lw s2, 12(sp)                   # Khôi phục thanh ghi s2 từ Stack
    lw s1, 8(sp)                    # Khôi phục thanh ghi s1 từ Stack
    lw s0, 4(sp)                    # Khôi phục thanh ghi s0 từ Stack
    lw ra, 0(sp)                    # Khôi phục địa chỉ trả về (return address) ban đầu

    addi sp, sp, 28                 # Giải phóng vùng nhớ Stack
    ret                             # Quay trở về nơi gọi hàm draw_rectangle

# ==========================================================
# VE HINH TRON (CIRCLE DRAWING)
# ==========================================================
draw_circle:
    addi sp, sp, -32                # Mở rộng vùng nhớ Stack để lưu các thanh ghi bảo toàn dữ liệu
    sw ra, 0(sp)                    # Lưu địa chỉ trả về (return address)
    sw s0, 4(sp)                    # Lưu thanh ghi s0
    sw s1, 8(sp)                    # Lưu thanh ghi s1
    sw s2, 12(sp)                   # Lưu thanh ghi s2
    sw s3, 16(sp)                   # Lưu thanh ghi s3
    sw s4, 20(sp)                   # Lưu thanh ghi s4
    sw s5, 24(sp)                   # Lưu thanh ghi s5
    sw s6, 28(sp)                   # Lưu thanh ghi s6

    mv s0, a0                       # s0 = xc (Tọa độ X của tâm đường tròn)
    mv s1, a1                       # s1 = yc (Tọa độ Y của tâm đường tròn)
    mv s5, a2                       # s5 = r (Bán kính đường tròn)
    mv s6, a3                       # s6 = color (Màu sắc cần vẽ)

    mv s2, s5                       # Khởi tạo s2: x = r
    li s3, 0                        # Khởi tạo s3: y = 0
    li s4, 0                        # Khởi tạo s4: biến quyết định d = 0 (tạm thời)

    li t0, 1                        # t0 = 1
    sub s4, t0, s5                  # Tính giá trị d ban đầu: d = 1 - r

loop_circle:
    blt s2, s3, end_circle          # Nếu x < y, dừng vòng lặp (đã vẽ xong toàn bộ các cung)

    # =========================
    # 8 POINTS PLOTTING INLINE (Vẽ đồng thời 8 điểm đối xứng qua tâm)
    # =========================

    # Cung 1: (xc + x, yc + y)
    mv t1, s0                       # t1 = xc
    add t1, t1, s2                  # t1 = xc + x
    mv t2, s1                       # t2 = yc
    add t2, t2, s3                  # t2 = yc + y
    jal plot_pixel                  # Gọi hàm tô màu pixel tại (t1, t2)

    # Cung 2: (xc - x, yc + y)
    mv t1, s0                       # t1 = xc
    sub t1, t1, s2                  # t1 = xc - x
    mv t2, s1                       # t2 = yc
    add t2, t2, s3                  # t2 = yc + y
    jal plot_pixel                  # Gọi hàm tô màu pixel tại (t1, t2)

    # Cung 3: (xc + x, yc - y)
    mv t1, s0                       # t1 = xc
    add t1, t1, s2                  # t1 = xc + x
    mv t2, s1                       # t2 = yc
    sub t2, t2, s3                  # t2 = yc - y
    jal plot_pixel                  # Gọi hàm tô màu pixel tại (t1, t2)

    # Cung 4: (xc - x, yc - y)
    mv t1, s0                       # t1 = xc
    sub t1, t1, s2                  # t1 = xc - x
    mv t2, s1                       # t2 = yc
    sub t2, t2, s3                  # t2 = yc - y
    jal plot_pixel                  # Gọi hàm tô màu pixel tại (t1, t2)

    # Cung 5: (xc + y, yc + x)
    mv t1, s0                       # t1 = xc
    add t1, t1, s3                  # t1 = xc + y
    mv t2, s1                       # t2 = yc
    add t2, t2, s2                  # t2 = yc + x
    jal plot_pixel                  # Gọi hàm tô màu pixel tại (t1, t2)

    # Cung 6: (xc - y, yc + x)
    mv t1, s0                       # t1 = xc
    sub t1, t1, s3                  # t1 = xc - y
    mv t2, s1                       # t2 = yc
    add t2, t2, s2                  # t2 = yc + x
    jal plot_pixel                  # Gọi hàm tô màu pixel tại (t1, t2)

    # Cung 7: (xc + y, yc - x)
    mv t1, s0                       # t1 = xc
    add t1, t1, s3                  # t1 = xc + y
    mv t2, s1                       # t2 = yc
    sub t2, t2, s2                  # t2 = yc - x
    jal plot_pixel                  # Gọi hàm tô màu pixel tại (t1, t2)

    # Cung 8: (xc - y, yc - x)
    mv t1, s0                       # t1 = xc
    sub t1, t1, s3                  # t1 = xc - y
    mv t2, s1                       # t2 = yc
    sub t2, t2, s2                  # t2 = yc - x
    jal plot_pixel                  # Gọi hàm tô màu pixel tại (t1, t2)

    # =========================

    addi s3, s3, 1                  # Tăng tọa độ y lên 1 đơn vị: y++

    # Kiểm tra biến quyết định d để cập nhật bước tiếp theo
    li t0, 0                        # t0 = 0
    bge s4, t0, update_case2        # Nếu d >= 0, nhảy đến trường hợp 2 (chọn điểm nằm phía trong)

case1:
    # Trường hợp d < 0: d = d + 2*y + 1 (giữ nguyên x)
    slli t1, s3, 1                  # t1 = 2 * y
    addi t1, t1, 1                  # t1 = 2 * y + 1
    add s4, s4, t1                  # Cập nhật thông số d: d += t1
    j loop_circle                   # Quay lại vòng lặp vẽ điểm tiếp theo

update_case2:
    addi s2, s2, -1                 # Giảm tọa độ x đi 1 đơn vị: x--

    # Trường hợp d >= 0: d = d + 2*(y - x) + 1
    sub t1, s3, s2                  # t1 = y - x
    slli t1, t1, 1                  # t1 = 2 * (y - x)
    addi t1, t1, 1                  # t1 = 2 * (y - x) + 1
    add s4, s4, t1                  # Cập nhật thông số d: d += t1

    j loop_circle                   # Quay lại vòng lặp vẽ điểm tiếp theo

end_circle:
    lw ra, 0(sp)                    # Khôi phục địa chỉ trả về từ Stack
    lw s0, 4(sp)                    # Khôi phục thanh ghi s0
    lw s1, 8(sp)                    # Khôi phục thanh ghi s1
    lw s2, 12(sp)                   # Khôi phục thanh ghi s2
    lw s3, 16(sp)                   # Khôi phục thanh ghi s3
    lw s4, 20(sp)                   # Khôi phục thanh ghi s4
    lw s5, 24(sp)                   # Khôi phục thanh ghi s5
    lw s6, 28(sp)                   # Khôi phục thanh ghi s6
    addi sp, sp, 32                 # Giải phóng vùng nhớ Stack
    ret                             # Quay trở về nơi gọi hàm draw_circle

plot_pixel:
    bltz t1, pp_ret                 # Nếu tọa độ X < 0, bỏ qua không vẽ để bảo vệ bộ nhớ
    bltz t2, pp_ret                 # Nếu tọa độ Y < 0, bỏ qua không vẽ để bảo vệ bộ nhớ

    li t3, DISPLAY_WIDTH            # t3 = Chiều rộng màn hình đồ họa
    bge t1, t3, pp_ret              # Nếu tọa độ X >= DISPLAY_WIDTH, bỏ qua không vẽ

    li t3, DISPLAY_HEIGHT           # t3 = Chiều cao màn hình đồ họa
    bge t2, t3, pp_ret              # Nếu tọa độ Y >= DISPLAY_HEIGHT, bỏ qua không vẽ

    # Tính toán địa chỉ ô nhớ pixel: Base + (y * DISPLAY_WIDTH + x) * 4
    li t3, DISPLAY_WIDTH            # t3 = Chiều rộng màn hình
    mul t4, t2, t3                  # t4 = y * DISPLAY_WIDTH
    add t4, t4, t1                  # t4 = (y * DISPLAY_WIDTH) + x
    slli t4, t4, 2                  # Nhân nhân 4 (dịch trái 2 bit) để đổi sang đơn vị byte

    li t5, BITMAP_BASE              # t5 = Địa chỉ gốc Bitmap Display
    add t4, t4, t5                  # t4 = Địa chỉ chính xác tuyệt đối của pixel trên RAM

    sw s6, 0(t4)                    # Ghi mã màu lưu từ s6 trực tiếp vào RAM để hiển thị pixel

pp_ret:
    ret                             # Quay trở lại vị trí gọi trong hàm vẽ hình tròn

# ==========================================================
# FLOOD FILL
# ==========================================================
flood_fill:
    addi sp, sp, -40                # Mở rộng vùng nhớ Stack hệ thống để lưu các thanh ghi bảo toàn dữ liệu

    sw ra, 0(sp)                    # Lưu địa chỉ trả về (return address)
    sw s0, 4(sp)                    # Lưu thanh ghi s0
    sw s1, 8(sp)                    # Lưu thanh ghi s1
    sw s2, 12(sp)                   # Lưu thanh ghi s2
    sw s3, 16(sp)                   # Lưu thanh ghi s3
    sw s4, 20(sp)                   # Lưu thanh ghi s4
    sw s5, 24(sp)                   # Lưu thanh ghi s5
    sw s6, 28(sp)                   # Lưu thanh ghi s6
    sw s7, 32(sp)                   # Lưu thanh ghi s7
    sw s8, 36(sp)                   # Lưu thanh ghi s8

    mv s0, a0                       # s0 = start x (Tọa độ X điểm bắt đầu)
    mv s1, a1                       # s1 = start y (Tọa độ Y điểm bắt đầu)
    mv s2, a2                       # s2 = new color (Màu mới cần tô loang)

    # --------------------------------------------------
    # Kiem tra toa do hop le
    # --------------------------------------------------

    bltz s0, fill_exit              # Nếu x < 0, tọa độ không hợp lệ -> Thoát
    bltz s1, fill_exit              # Nếu y < 0, tọa độ không hợp lệ -> Thoát

    li t0, DISPLAY_WIDTH            # t0 = Chiều rộng màn hình
    bge s0, t0, fill_exit           # Nếu x >= DISPLAY_WIDTH -> Thoát

    li t0, DISPLAY_HEIGHT           # t0 = Chiều cao màn hình
    bge s1, t0, fill_exit           # Nếu y >= DISPLAY_HEIGHT -> Thoát

    # --------------------------------------------------
    # Lay mau goc tai diem bat dau
    # --------------------------------------------------

    li t0, DISPLAY_WIDTH            # t0 = Chiều rộng màn hình
    mul t1, s1, t0                  # t1 = y * DISPLAY_WIDTH
    add t1, t1, s0                  # t1 = (y * DISPLAY_WIDTH) + x
    slli t1, t1, 2                  # Nhân nhân 4 (dịch trái 2 bit) để đổi sang đơn vị byte

    li t2, BITMAP_BASE              # t2 = Địa chỉ gốc Bitmap Display
    add t1, t1, t2                  # t1 = Địa chỉ chính xác của pixel bắt đầu trên RAM

    lw s3, 0(t1)                    # s3 = old_color (Đọc màu gốc hiện tại của pixel)

    # Neu mau moi = mau cu => thoat

    beq s2, s3, fill_exit           # Nếu màu mới trùng màu cũ, không cần tô -> Thoát luôn để tránh lặp vô hạn

    # --------------------------------------------------
    # Khoi tao stack
    # --------------------------------------------------

    la s4, fill_stack               # s4 = Địa chỉ đáy của mảng fill_stack (stack base)
    mv s5, s4                       # s5 = Con trỏ đỉnh stack (stack top), ban đầu ở đáy stack

    # push(start_x,start_y)

    sw s0, 0(s5)                    # Lưu tọa độ X hiện tại vào ô nhớ đỉnh stack
    sw s1, 4(s5)                    # Lưu tọa độ Y hiện tại vào ô nhớ tiếp theo của đỉnh stack
    addi s5, s5, 8                  # Tăng con trỏ đỉnh stack lên 8 byte (để chuẩn bị cho phần tử tiếp theo)

# MAIN LOOP (Vòng lặp chính xử lý thuật toán loang)
fill_loop:

    # stack rong ?

    beq s5, s4, fill_exit           # Nếu con trỏ đỉnh bằng con trỏ đáy -> Stack rỗng -> Đã tô xong toàn bộ, thoát

    # pop

    addi s5, s5, -8                 # Giảm con trỏ đỉnh stack đi 8 byte để trỏ vào phần tử vừa nạp

    lw s6, 0(s5)                    # s6 = x (Lấy tọa độ X ra khỏi stack)
    lw s7, 4(s5)                    # s7 = y (Lấy tọa độ Y ra khỏi stack)

    # --------------------------------------------------
    # Kiem tra bien man hinh
    # --------------------------------------------------

    bltz s6, fill_loop              # Nếu x lấy ra < 0, bỏ qua điểm này, quay lại vòng lặp
    bltz s7, fill_loop              # Nếu y lấy ra < 0, bỏ qua điểm này, quay lại vòng lặp

    li t0, DISPLAY_WIDTH            # t0 = Chiều rộng màn hình
    bge s6, t0, fill_loop           # Nếu x >= DISPLAY_WIDTH, bỏ qua điểm này, quay lại vòng lặp

    li t0, DISPLAY_HEIGHT           # t0 = Chiều cao màn hình
    bge s7, t0, fill_loop           # Nếu y >= DISPLAY_HEIGHT, bỏ qua điểm này, quay lại vòng lặp

    # --------------------------------------------------
    # Tinh dia chi pixel
    # --------------------------------------------------

    li t0, DISPLAY_WIDTH            # t0 = Chiều rộng màn hình

    mul t1, s7, t0                  # t1 = y * DISPLAY_WIDTH
    add t1, t1, s6                  # t1 = (y * DISPLAY_WIDTH) + x
    slli t1, t1, 2                  # Nhân nhân 4 để chuyển sang đơn vị byte

    li t2, BITMAP_BASE              # t2 = Địa chỉ gốc Bitmap Display
    add t1, t1, t2                  # t1 = Địa chỉ ô RAM của pixel hiện tại đang xét

    # --------------------------------------------------
    # Chi xu ly pixel co mau goc
    # --------------------------------------------------

    lw t3, 0(t1)                    # t3 = Đọc mã màu hiện tại của pixel từ RAM

    bne t3, s3, fill_loop           # Nếu màu pixel khác màu gốc (đã tô hoặc là biên), bỏ qua không xử lý

    # --------------------------------------------------
    # To mau
    # --------------------------------------------------

    sw s2, 0(t1)                    # Ghi mã màu mới từ s2 trực tiếp vào RAM để tô màu cho pixel này

    # --------------------------------------------------
    # PUSH LEFT (Đưa điểm bên trái lân cận vào stack)
    # --------------------------------------------------

    addi t4, s6, -1                 # t4 = x - 1

    sw t4, 0(s5)                    # Lưu tọa độ X mới (trái) vào đỉnh stack
    sw s7, 4(s5)                    # Lưu tọa độ Y hiện tại vào đỉnh stack
    addi s5, s5, 8                  # Tăng con trỏ đỉnh stack lên 8 byte

    # --------------------------------------------------
    # PUSH RIGHT (Đưa điểm bên phải lân cận vào stack)
    # --------------------------------------------------

    addi t4, s6, 1                  # t4 = x + 1

    sw t4, 0(s5)                    # Lưu tọa độ X mới (phải) vào đỉnh stack
    sw s7, 4(s5)                    # Lưu tọa độ Y hiện tại vào đỉnh stack
    addi s5, s5, 8                  # Tăng con trỏ đỉnh stack lên 8 byte

    # --------------------------------------------------
    # PUSH UP (Đưa điểm phía trên lân cận vào stack)
    # --------------------------------------------------

    addi t4, s7, -1                 # t4 = y - 1

    sw s6, 0(s5)                    # Lưu tọa độ X hiện tại vào đỉnh stack
    sw t4, 4(s5)                    # Lưu tọa độ Y mới (trên) vào đỉnh stack
    addi s5, s5, 8                  # Tăng con trỏ đỉnh stack lên 8 byte

    # --------------------------------------------------
    # PUSH DOWN (Đưa điểm phía dưới lân cận vào stack)
    # --------------------------------------------------

    addi t4, s7, 1                  # t4 = y + 1

    sw s6, 0(s5)                    # Lưu tọa độ X hiện tại vào đỉnh stack
    sw t4, 4(s5)                    # Lưu tọa độ Y mới (dưới) vào đỉnh stack
    addi s5, s5, 8                  # Tăng con trỏ đỉnh stack lên 8 byte

    j fill_loop                     # Tiếp tục vòng lặp để lấy điểm tiếp theo từ stack ra xử lý

# EXIT (Khôi phục dữ liệu hệ thống trước khi thoát hàm)
fill_exit:

    lw s8, 36(sp)                   # Khôi phục thanh ghi s8 từ Stack
    lw s7, 32(sp)                   # Khôi phục thanh ghi s7 từ Stack
    lw s6, 28(sp)                   # Khôi phục thanh ghi s6 từ Stack
    lw s5, 24(sp)                   # Khôi phục thanh ghi s5 từ Stack
    lw s4, 20(sp)                   # Khôi phục thanh ghi s4 từ Stack
    lw s3, 16(sp)                   # Khôi phục thanh ghi s3 từ Stack
    lw s2, 12(sp)                   # Khôi phục thanh ghi s2 từ Stack
    lw s1, 8(sp)                    # Khôi phục thanh ghi s1 từ Stack
    lw s0, 4(sp)                    # Khôi phục thanh ghi s0 từ Stack
    lw ra, 0(sp)                    # Khôi phục địa chỉ trả về (return address) ban đầu

    addi sp, sp, 40                 # Giải phóng 40 byte không gian vùng nhớ Stack hệ thống
    ret                             # Quay trở về hàm gọi flood_fill

# =================================================================
# HÀM CHUYỂN ĐỔI CHUỖI SANG SỐ (String to Integer - atoi)
# =================================================================
atoi:
    # Đầu vào: a0 = Con trỏ chuỗi hiện tại
    # Đầu ra:  a0 = Giá trị số nguyên, a1 = Vị trí con trỏ dừng lại mới, a2 = Trạng thái (0: OK, 1: Lỗi)
atoi_skip_space:
    lb t0, 0(a0)                    # Đọc ký tự hiện tại từ chuỗi vào t0
    li t1, ' '                      # Mã ASCII của ký tự khoảng trắng ' '
    bne t0, t1, atoi_init           # Nếu ký tự không phải khoảng trắng, nhảy đến khởi tạo số
    addi a0, a0, 1                  # Nếu là khoảng trắng, tiến con trỏ chuỗi lên 1 byte
    j atoi_skip_space               # Tiếp tục vòng lặp bỏ qua khoảng trắng

atoi_init:
    li t1, '0'                      # t1 = Mã ASCII của ký tự '0' (giới hạn dưới)
    li t2, '9'                      # t2 = Mã ASCII của ký tự '9' (giới hạn trên)
    blt t0, t1, atoi_err            # Nếu ký tự nhỏ hơn '0', chuỗi không hợp lệ -> Nhảy đến báo lỗi
    bgt t0, t2, atoi_err            # Nếu ký tự lớn hơn '9', chuỗi không hợp lệ -> Nhảy đến báo lỗi
    li t3, 0                        # Khởi tạo kết quả tích lũy ban đầu t3 = 0

atoi_loop:
    lb t0, 0(a0)                    # Đọc ký tự tại vị trí con trỏ hiện tại vào t0
    blt t0, t1, atoi_success        # Nếu ký tự nhỏ hơn '0' (ví dụ: khoảng trắng hoặc '\0'), kết thúc dịch thành công
    bgt t0, t2, atoi_success        # Nếu ký tự lớn hơn '9', kết thúc dịch thành công
    
    addi t0, t0, -48                # Chuyển đổi từ mã ASCII sang giá trị số thực (Ký tự trừ đi 48)
    li t4, 10                       # t4 = 10
    mul t3, t3, t4                  # Nhân giá trị tích lũy trước đó với 10 (Dịch hàng đơn vị)
    add t3, t3, t0                  # Cộng thêm giá trị của chữ số vừa chuyển đổi
    addi a0, a0, 1                  # Tiến con trỏ chuỗi lên 1 byte để xét ký tự tiếp theo
    j atoi_loop                     # Tiếp tục vòng lặp xử lý chữ số tiếp theo

atoi_success:
    mv a1, a0                       # Trả về địa chỉ con trỏ dừng kế tiếp tại a1
    mv a0, t3                       # Trả về kết quả số nguyên đã chuyển đổi tại a0
    li a2, 0                        # Trả về mã trạng thái thành công (a2 = 0)
    ret                             # Quay về nơi gọi hàm atoi

atoi_err:
    li a2, 1                        # Trả về mã trạng thái lỗi định dạng (a2 = 1)
    ret                             # Quay về nơi gọi hàm atoi

# =================================================================
# CÁC HÀM GIAO TIẾP GHI/XUẤT DISPLAY MMIO
# =================================================================
print_char_mmio:
    li t5, DSP_CTRL                 # Tải địa chỉ thanh ghi điều khiển màn hình vào t5
wait_dsp:
    lw t6, 0(t5)                    # Đọc trạng thái từ thanh ghi điều khiển vào t6
    andi t6, t6, 1                  # Trích xuất bit Ready (bit cuối cùng)
    beqz t6, wait_dsp               # Nếu bit ready == 0, tiếp tục đợi màn hình sẵn sàng
    li t5, DSP_DATA                 # Tải địa chỉ thanh ghi dữ liệu màn hình vào t5
    sb a0, 0(t5)                    # Ghi 1 byte ký tự từ a0 vào thanh ghi dữ liệu để hiển thị
    ret                             # Quay về nơi gọi hàm

print_str_mmio:
    addi sp, sp, -8                 # Mở rộng Stack để bảo toàn dữ liệu thanh ghi
    sw ra, 0(sp)                    # Lưu địa chỉ trả về (return address)
    sw s2, 4(sp)                    # Lưu thanh ghi s2
    mv s2, a0                       # s2 = Địa chỉ chuỗi ký tự bắt đầu in
str_loop:
    lb a0, 0(s2)                    # Đọc ký tự hiện tại từ chuỗi vào a0
    beqz a0, str_end                # Nếu gặp ký tự Null (\0), kết thúc chuỗi -> Thoát
    jal print_char_mmio             # Gọi hàm in ký tự trong a0 ra màn hình MMIO
    addi s2, s2, 1                  # Tiến con trỏ chuỗi lên 1 byte để lấy ký tự tiếp theo
    j str_loop                      # Quay lại vòng lặp in ký tự kế tiếp
str_end:
    lw s2, 4(sp)                    # Khôi phục giá trị cũ của thanh ghi s2 từ Stack
    lw ra, 0(sp)                    # Khôi phục địa chỉ trả về ban đầu
    addi sp, sp, 8                  # Giải phóng không gian vùng nhớ Stack
    ret                             # Quay trở về nơi gọi hàm print_str_mmio
