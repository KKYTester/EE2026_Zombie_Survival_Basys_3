exec(open('gun_sprite.py').read().split("def frame")[0])   # GUN, FLASH, P
pal_order=['.','K','w','g','d','S','s','c','Y','O','W']
def rgb565(c): r,g,b=c; return ((r*31+127)//255)<<11 | ((g*63+127)//255)<<5 | ((b*31+127)//255)
cols={ch:rgb565(P[ch]) for ch in pal_order[1:]}
def rowbits(row,w): return ''.join(format(pal_order.index(ch),'04b') for ch in row)
L=[]
L.append("`timescale 1ns / 1ps")
L.append("// First-person weapon: a pistol held in the right hand, bottom-centre of the")
L.append("// play view (28x24 sprite at x=41..68, y=40..63). recoil moves it down 2 px;")
L.append("// flash draws a muzzle flash above the slide. Drawn over the world, under the")
L.append("// HUD (crosshair stays on top). Combinational; sprite ROM generated from")
L.append("// gun_sprite.py (palette index per pixel, 0 = transparent).")
L.append("module weapon_overlay(input wire [6:0] px, input wire [5:0] py,")
L.append("    input wire show, input wire recoil, input wire flash,")
L.append("    input wire [15:0] pixel_in, output reg [15:0] pixel_out);")
L.append("    localparam X0=41, Y0=40, W=28, H=24, FX=44, FW=10, FH=6;")
L.append("    wire [5:0] gy0 = recoil ? Y0+2 : Y0;")
L.append("    wire [6:0] sx = px - X0;")
L.append("    wire [5:0] sy = py - gy0;")
L.append("    wire in_gun = show && px>=X0 && px<X0+W && py>=gy0 && sy<H;")
L.append("    reg [111:0] gun_row;")
L.append("    always @* begin")
L.append("        case(sy)")
for i,row in enumerate(GUN): L.append(f"            {i}: gun_row=112'b{rowbits(row,28)};")
L.append("            default: gun_row=0;")
L.append("        endcase")
L.append("    end")
L.append("    wire [3:0] gun_index = gun_row[111-sx*4 -: 4];")
L.append("    wire [5:0] fy0 = gy0 - FH;")
L.append("    wire [6:0] fx = px - FX;")
L.append("    wire [5:0] fy = py - fy0;")
L.append("    wire in_flash = show && flash && px>=FX && px<FX+FW && py>=fy0 && fy<FH;")
L.append("    reg [39:0] flash_row;")
L.append("    always @* begin")
L.append("        case(fy)")
for i,row in enumerate(FLASH): L.append(f"            {i}: flash_row=40'b{rowbits(row,10)};")
L.append("            default: flash_row=0;")
L.append("        endcase")
L.append("    end")
L.append("    wire [3:0] flash_index = flash_row[39-fx*4 -: 4];")
L.append("    function [15:0] colour;")
L.append("        input [3:0] i;")
L.append("        case(i)")
for k,ch in enumerate(pal_order[1:],1): L.append(f"            {k}: colour=16'h{cols[ch]:04X};   // {ch}")
L.append("            default: colour=16'h0000;")
L.append("        endcase")
L.append("    endfunction")
L.append("    always @* begin")
L.append("        pixel_out=pixel_in;")
L.append("        if(in_gun && gun_index!=0) pixel_out=colour(gun_index);")
L.append("        if(in_flash && flash_index!=0) pixel_out=colour(flash_index);")
L.append("    end")
L.append("endmodule")
open('weapon_overlay.v','w').write('\n'.join(L)+'\n')
# Golden frames (independent of the Verilog encoding): idle, recoil+flash, over a known background.
def frame_px(recoil,flash):
    out=[]
    x0,y0=41,40+(2 if recoil else 0)
    for y in range(64):
        for x in range(96):
            v=((x*7+y*13)&0xFFFF)          # background pattern = tb pixel_in
            r,c=y-y0,x-x0
            if 0<=r<24 and 0<=c<28 and GUN[r][c]!='.': v=cols[GUN[r][c]]
            if flash:
                fr,fc=y-(y0-6),x-44
                if 0<=fr<6 and 0<=fc<10 and FLASH[fr][fc]!='.': v=cols[FLASH[fr][fc]]
            out.append(v)
    return out
g=frame_px(0,0)+frame_px(1,1)
open('weapon_golden.hex','w').write('\n'.join(format(v,'04x') for v in g)+'\n')
print("ok", len(g))
