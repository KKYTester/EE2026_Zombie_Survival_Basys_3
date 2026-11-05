from PIL import Image, ImageDraw
GUN = [
"....K.....K.................",
"...KwK...KwK................",
"..KKKKKKKKKKKK..............",
"..KwwwwwwwwwgK..............",
"..KwggggggggdK..............",
"..KggggggggggdK.............",
"..KgggKKKKgggdK.............",
"..KgggKddKgggdK.............",
"..KgggKKKKgggdK.............",
"..KggggggggggdK.............",
"..KddddddddddK..............",
".KSSKKgggggKKSK.............",
"KSSSSKgggggKSSSK............",
"KSSSSSKdddKSSSSSK...........",
"KsSSSSSKKKSSSSSSSK..........",
".KsSSSSSSSSSSSSSSSK.........",
"..KssSSSSSSSSSSSSSsK........",
"...KKssSSSSSSSSSSssccK......",
".....KKsssSSSSSsscccccK.....",
".......KccsssssscccccccK....",
"........KcccccccccccccccK...",
".........KcccccccccccccccK..",
"..........KcccccccccccccccK.",
"...........KcccccccccccccccK",
]
FLASH = [
"....YY....",
"..Y.YY.Y..",
"...YOOY...",
".YYOWWOYY.",
"..YOWWOY..",
"...YOOY...",
]
P={'K':(25,20,20),'w':(200,205,215),'g':(110,115,125),'d':(60,62,70),'S':(215,155,120),'s':(165,105,75),
   'c':(60,80,55),'Y':(255,230,60),'O':(255,140,20),'W':(255,255,255)}
def frame(fire, recoil, hud=True):
    im=Image.new("RGB",(96,64)); p=im.load()
    for y in range(64):
        for x in range(96): p[x,y]=(16,16,32) if y<32 else (49,44,49)
    x0,y0=41,40+(2 if recoil else 0)
    for r,row in enumerate(GUN):
        for c,ch in enumerate(row):
            if ch!='.' and 0<=y0+r<64 and x0+c<96: p[x0+c,y0+r]=P[ch]
    if fire:
        fx,fy=x0+3,y0-6
        for r,row in enumerate(FLASH):
            for c,ch in enumerate(row):
                if ch!='.': p[fx+c,fy+r]=P[ch]
    for i in (-2,-1,1,2): p[48+i,32]=(255,255,255); p[48,32+i]=(255,255,255)
    if hud:
        H=["01010","11111","11111","01110","00100"]
        for k in range(3):
            for r in range(5):
                for c in range(5):
                    if H[r][c]=='1': p[2+6*k+c,56+r]=(255,0,0)
    return im
S=5
out=Image.new("RGB",(2*(96*S+16)+16,64*S+40),(240,240,240)); d=ImageDraw.Draw(out)
for i,(n,f,r) in enumerate([("Idle",0,0),("Firing: recoil + muzzle flash",1,1)]):
    x=16+i*(96*S+16); d.text((x,8),n,fill=(0,0,0)); out.paste(frame(f,r).resize((96*S,64*S),Image.NEAREST),(x,24))
out.save("gun_mock2.png")
print(len(GUN), set(len(r) for r in GUN))
