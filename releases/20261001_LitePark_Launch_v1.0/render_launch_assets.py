#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parent
ASSETS = ROOT / "assets"
ICON = Image.open(ASSETS / "LitePark-icon-512.png").convert("RGBA")
PANEL = Image.open(ASSETS / "LitePark-demo-queue.png").convert("RGBA")
TRIGGER = Image.open(ASSETS / "LitePark-trigger.png").convert("RGBA")
URL = "https://github.com/victor-zhang-2026/LitePark"
ORANGE = "#E88743"
DEEP = "#BD642F"
INK = "#302A27"
BODY = "#685E58"
CREAM = "#FFF9F1"
PALE = "#F8E7D7"
RED = "#F04F48"
CN_FONT = "/System/Library/AssetsV2/com_apple_MobileAsset_Font8/86ba2c91f017a3749571a82f2c6d890ac7ffb2fb.asset/AssetData/PingFang.ttc"
EN_REG = "/System/Library/Fonts/HelveticaNeue.ttc"
EN_BOLD = "/System/Library/Fonts/HelveticaNeue.ttc"

def font(size, bold=False, cn=False):
    if cn:
        return ImageFont.truetype(CN_FONT, size, index=11 if bold else 3)
    return ImageFont.truetype(EN_BOLD if bold else EN_REG, size)

def canvas(size):
    w, h = size
    im = Image.new("RGB", size, CREAM)
    px = im.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        for x in range(w):
            glow = max(0, 1 - ((x-w*.82)**2 + (y-h*.2)**2)**.5/(w*.75))
            px[x, y] = (255, int(249-4*t+4*glow), int(241-8*t+7*glow))
    return im

def round_image(im, radius):
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0,0,*im.size), radius=radius, fill=255)
    out = Image.new("RGBA", im.size)
    out.paste(im, mask=mask)
    return out

def fit(im, box):
    x,y,w,h = box
    copy = im.copy()
    copy.thumbnail((w,h), Image.Resampling.LANCZOS)
    return copy, (x+(w-copy.width)//2, y+(h-copy.height)//2)

def shadow_paste(dst, src, xy, radius=26, blur=28, offset=16):
    layer = Image.new("RGBA", dst.size)
    mask = src.getchannel("A") if src.mode == "RGBA" else Image.new("L", src.size, 255)
    shadow = Image.new("RGBA", dst.size)
    sm = Image.new("L", dst.size)
    sm.paste(mask, (xy[0], xy[1]+offset))
    sm = sm.filter(ImageFilter.GaussianBlur(blur))
    shadow.paste((81,52,31,70), (0,0), sm)
    dst.alpha_composite(shadow)
    dst.alpha_composite(src, xy)

def text(draw, xy, value, size, *, bold=False, cn=False, fill=INK, spacing=12, anchor=None):
    draw.multiline_text(xy, value, font=font(size,bold,cn), fill=fill, spacing=spacing, anchor=anchor)

def header(im, cn=False):
    d=ImageDraw.Draw(im)
    logo,_=fit(ICON,(64,54,62,62)); im.alpha_composite(logo,(64,54))
    text(d,(144,69),"LitePark",30,bold=True,fill=INK)
    text(d,(im.width-64,75),"PARK IT NOW. PICK IT UP LATER.",16,bold=True,fill=DEEP,anchor="ra")

def panel_card(im, box):
    p,pos=fit(PANEL,box)
    p=round_image(p,42)
    shadow_paste(im,p,pos,blur=25,offset=14)

def badge(draw, xy, label):
    x,y=xy; draw.rounded_rectangle((x,y,x+360,y+54),radius=27,fill=ORANGE)
    text(draw,(x+180,y+27),label,20,bold=True,fill="white",anchor="mm")

def qr(size=240):
    im=Image.new("RGBA",(size,size),"white"); d=ImageDraw.Draw(im)
    d.rounded_rectangle((4,4,size-4,size-4),radius=28,outline=ORANGE,width=8)
    text(d,(size/2,size/2-18),"GitHub",36,bold=True,fill=INK,anchor="mm")
    text(d,(size/2,size/2+35),"OPEN",20,bold=True,fill=DEEP,anchor="mm")
    return im

def save_cards(outdir, size, language):
    outdir.mkdir(parents=True,exist_ok=True)
    cn=language=="cn"; w,h=size
    copy = {
      "cn":[
        ("01-cover.png","ChatGPT 对话，\n先停在这里","LitePark · macOS 对话停车位"),
        ("02-problem.png","历史记录保存了对话，\n却没有表达“稍后回来”","有些对话现在不处理，但不能忘记。"),
        ("03-workflow.png","一个很短的流程","打开对话 → 快捷键加入 → 稍后打开 → Done"),
        ("04-features.png","只做这一件事","手动排序 · 一键回到 ChatGPT · 本地保存"),
        ("05-privacy.png","保存队列，不保存内容","无账号 · 无统计 · 无遥测 · 不读取对话正文"),
        ("06-open-source.png","LitePark v1.0.0","免费开源 · macOS 13+ · GitHub 下载"),
      ],
      "en":[
        ("01-cover.png","Park a ChatGPT conversation.\nPick it up later.","LitePark · a lightweight macOS companion"),
        ("02-problem.png","History keeps conversations.\nIt doesn't create a later queue.","Some conversations need a clear place to wait."),
        ("03-workflow.png","A deliberately short loop","Open → shortcut → return later → mark done"),
        ("04-features.png","Focused on one job","Manual order · reopen in ChatGPT · local persistence"),
        ("05-privacy.png","Queue metadata stays local","No account · analytics · telemetry · conversation content"),
        ("06-open-source.png","LitePark v1.0.0","Free and open source · macOS 13+"),
      ]}[language]
    for i,(name,title,subtitle) in enumerate(copy):
        im=canvas(size).convert("RGBA"); d=ImageDraw.Draw(im); header(im,cn)
        if i==0:
            text(d,(64,190),title,72 if cn else 64,bold=True,cn=cn,spacing=16)
            text(d,(68,390),subtitle,30,cn=cn,fill=BODY)
            badge(d,(68,470),"CHATGPT DESKTOP · macOS")
            panel_card(im,(230,575,w-294,h-630))
        elif i==1:
            text(d,(64,190),title,58 if cn else 54,bold=True,cn=cn,spacing=14)
            text(d,(68,380),subtitle,28,cn=cn,fill=BODY)
            d.rounded_rectangle((64,510,w-64,890),radius=38,fill="#302A27")
            examples=["Product Research","Weekend Trip Ideas","Books to Read"]
            for n,label in enumerate(examples):
                yy=590+n*88; d.ellipse((100,yy,128,yy+28),outline=ORANGE,width=4)
                text(d,(156,yy-4),label,28,bold=True,fill="white")
            text(d,(64,970),"“Come back to this later.”" if not cn else "“这段对话之后还要回来。”",42,bold=True,cn=cn,fill=DEEP)
        elif i==2:
            text(d,(64,190),title,64,bold=True,cn=cn)
            text(d,(68,300),subtitle,28,cn=cn,fill=BODY)
            steps=[("1","Open ChatGPT" if not cn else "打开 ChatGPT 对话"),("2","Press Control + Option + L" if not cn else "按 Control + Option + L"),("3","Return from LitePark" if not cn else "稍后从 LitePark 返回"),("4","Mark it done" if not cn else "处理完后勾选 Done")]
            for n,(num,label) in enumerate(steps):
                yy=430+n*170; d.rounded_rectangle((64,yy,w-64,yy+128),radius=28,fill="white")
                d.ellipse((94,yy+29,164,yy+99),fill=PALE); text(d,(129,yy+64),num,28,bold=True,fill=DEEP,anchor="mm")
                text(d,(200,yy+42),label,31,bold=True,cn=cn)
        elif i==3:
            text(d,(64,190),title,64,bold=True,cn=cn)
            text(d,(68,300),subtitle,28,cn=cn,fill=BODY)
            panel_card(im,(220,410,w-280,h-470))
        elif i==4:
            text(d,(64,190),title,64 if cn else 60,bold=True,cn=cn)
            text(d,(68,300),subtitle,28,cn=cn,fill=BODY)
            items=[("TITLE", "Only the conversation title" if not cn else "仅保存对话标题"),("ORDER","Your manual queue order" if not cn else "保存手动排序"),("LOCAL","Stored on this Mac" if not cn else "只保存在这台 Mac")]
            for n,(tag,desc) in enumerate(items):
                yy=450+n*190; d.rounded_rectangle((64,yy,w-64,yy+142),radius=30,fill="white")
                text(d,(102,yy+34),tag,18,bold=True,fill=ORANGE)
                text(d,(102,yy+72),desc,31,bold=True,cn=cn)
            text(d,(w/2,h-150),"No prompts. No responses." if not cn else "不保存 Prompt，也不保存回复。",30,bold=True,cn=cn,fill=DEEP,anchor="mm")
        else:
            d.rounded_rectangle((0,0,w,h),fill="#302A27")
            logo,_=fit(ICON,(64,70,120,120)); im.alpha_composite(logo,(64,70))
            text(d,(214,96),title,54,bold=True,cn=cn,fill="white")
            text(d,(68,300),subtitle,32,bold=True,cn=cn,fill="#F4CBA8")
            q=qr(300); im.alpha_composite(q,(w-390,500))
            text(d,(68,520),"Download / Star / Feedback",30,bold=True,fill="white")
            text(d,(68,585),"github.com/\nvictor-zhang-2026/\nLitePark",34,bold=True,fill="#F4CBA8",spacing=10)
            text(d,(w/2,h-130),"ChatGPT Desktop must be running" if not cn else "使用时需要启动 ChatGPT Desktop",24,bold=True,cn=cn,fill="#D9CDC6",anchor="mm")
        im.convert("RGB").save(outdir/name,quality=95)

def covers():
    out=ROOT/"wechat"; out.mkdir(exist_ok=True); (out/"images").mkdir(exist_ok=True)
    im=canvas((900,383)).convert("RGBA");d=ImageDraw.Draw(im)
    d.ellipse((565,-210,1010,235),fill="#F7DDC8")
    d.ellipse((-170,250,260,680),fill="#FCECDD")
    logo,pos=fit(ICON,(62,88,90,90)); im.alpha_composite(logo,pos)
    text(d,(178,95),"LitePark",42,bold=True)
    text(d,(64,205),"ChatGPT 对话，先停在这里",27,bold=True,cn=True,fill=DEEP)
    text(d,(66,257),"PARK IT NOW. PICK IT UP LATER.",13,bold=True,fill=BODY)
    p,pos=fit(PANEL,(580,18,280,350));p=round_image(p,18);shadow_paste(im,p,pos,blur=14,offset=8)
    t,pos=fit(TRIGGER,(500,252,96,96));im.alpha_composite(t,pos)
    im.convert("RGB").save(out/"cover-900x383.png")

    im=canvas((900,900)).convert("RGBA");d=ImageDraw.Draw(im)
    d.ellipse((475,-120,980,385),fill="#F7DDC8")
    faded=PANEL.copy();faded.putalpha(38);p,pos=fit(faded,(470,250,380,480));im.alpha_composite(p,pos)
    logo,pos=fit(ICON,(300,155,300,300));shadow_paste(im,logo,pos,blur=22,offset=12)
    text(d,(450,525),"LitePark",64,bold=True,anchor="mm")
    text(d,(450,610),"ChatGPT 对话，先停在这里",33,bold=True,cn=True,fill=DEEP,anchor="mm")
    text(d,(450,690),"PARK IT NOW. PICK IT UP LATER.",16,bold=True,fill=BODY,anchor="mm")
    im.convert("RGB").save(out/"cover-square.png")
    PANEL.save(out/"images/product-demo-queue.png")
    ICON.save(out/"images/litepark-logo.png")

def wechat_story_images():
    out=ROOT/"wechat/images";out.mkdir(parents=True,exist_ok=True)
    specs=[
      ("01-floating-workflow.png","平时只留一个小入口","鼠标移到悬浮球，LitePark 才展开。"),
      ("02-manual-order.png","顺序由你决定","拖动当前行右侧的 Handle，队列立即保存。"),
      ("03-return-to-chatgpt.png","从 LitePark 回到原对话","点击整行，LitePark 唤起 ChatGPT 并验证标题。"),
      ("04-local-privacy.png","只保存本地队列","标题、顺序与本地 ID 留在 Mac；不保存对话正文。"),
      ("05-done.png","处理完，轻轻勾掉","Done 只移出 LitePark 队列，不会删除 ChatGPT 对话。"),
    ]
    for i,(name,title,subtitle) in enumerate(specs):
        im=canvas((1200,800)).convert("RGBA");d=ImageDraw.Draw(im)
        logo,pos=fit(ICON,(62,52,68,68));im.alpha_composite(logo,pos)
        text(d,(150,65),"LitePark",30,bold=True)
        text(d,(64,168),title,50,bold=True,cn=True)
        text(d,(66,240),subtitle,25,cn=True,fill=BODY)
        if i==0:
            d.rounded_rectangle((64,335,1136,720),radius=34,fill="#ECE8E3")
            d.rounded_rectangle((64,335,1136,395),radius=30,fill="#F7F4F0")
            for x,c in [(98,"#FF5F57"),(132,"#FEBB2E"),(166,"#28C840")]:d.ellipse((x,354,x+20,374),fill=c)
            for n,w in enumerate([550,700,620]):d.rounded_rectangle((135,460+n*58,135+w,476+n*58),radius=8,fill="#CBC4BE")
            t,pos=fit(TRIGGER,(970,500,135,135));im.alpha_composite(t,pos)
            text(d,(1090,660),"需要时出现",22,bold=True,cn=True,fill=DEEP,anchor="ra")
        elif i==1:
            panel_card(im,(90,330,630,430))
            d.rounded_rectangle((770,360,1110,640),radius=28,fill="white")
            text(d,(810,400),"Product Research",23,bold=True)
            text(d,(810,480),"Weekend Trip Ideas",23,bold=True)
            d.line((792,458,1080,458),fill=ORANGE,width=6)
            text(d,(940,585),"Drag to reorder",21,bold=True,fill=DEEP,anchor="mm")
        elif i==2:
            panel_card(im,(70,340,460,390))
            d.rounded_rectangle((690,350,1120,705),radius=30,fill="#302A27")
            text(d,(905,410),"ChatGPT",33,bold=True,fill="white",anchor="mm")
            text(d,(735,490),"Product Research",27,bold=True,fill="white")
            d.rounded_rectangle((735,555,1075,625),radius=16,fill="#3B3734")
            text(d,(905,590),"Opened and verified",20,bold=True,fill="#F4CBA8",anchor="mm")
            d.line((570,525,650,525),fill=ORANGE,width=8)
            d.polygon([(650,525),(625,507),(625,543)],fill=ORANGE)
        elif i==3:
            labels=[("TITLE","对话标题"),("ORDER","手动顺序"),("LOCAL ID","本地项目 ID")]
            for n,(tag,desc) in enumerate(labels):
                yy=350+n*118;d.rounded_rectangle((64,yy,710,yy+88),radius=22,fill="white")
                text(d,(94,yy+18),tag,16,bold=True,fill=ORANGE);text(d,(250,yy+25),desc,24,bold=True,cn=True)
            d.rounded_rectangle((780,350,1136,672),radius=30,fill="#302A27")
            text(d,(958,415),"不保存",28,bold=True,cn=True,fill="#F4CBA8",anchor="mm")
            text(d,(958,505),"Prompt\n回复\n截图\n账号信息",27,bold=True,cn=True,fill="white",spacing=16,anchor="ma")
        else:
            d.rounded_rectangle((70,360,540,650),radius=30,fill="#302A27")
            d.ellipse((112,421,142,451),outline=ORANGE,width=4)
            text(d,(190,430),"Product Research",28,bold=True,fill="white")
            text(d,(115,535),"点击 Done",22,bold=True,cn=True,fill="#F4CBA8")
            d.line((575,505,650,505),fill=ORANGE,width=8)
            d.polygon([(650,505),(625,487),(625,523)],fill=ORANGE)
            d.rounded_rectangle((690,360,1130,650),radius=30,fill="#302A27")
            text(d,(910,435),"LitePark",32,bold=True,fill="white",anchor="mm")
            text(d,(910,520),"3",72,bold=True,fill="#F4CBA8",anchor="mm")
            text(d,(910,590),"队列继续保持清爽",21,bold=True,cn=True,fill="white",anchor="mm")
        im.convert("RGB").save(out/name)

if __name__ == "__main__":
    save_cards(ROOT/"xiaohongshu/images",(1080,1440),"cn")
    save_cards(ROOT/"linkedin/images",(1080,1350),"en")
    (ROOT/"x/images").mkdir(parents=True,exist_ok=True)
    for name in ["01-cover.png","03-workflow.png","05-privacy.png","06-open-source.png"]:
        Image.open(ROOT/"linkedin/images"/name).save(ROOT/"x/images"/name)
    covers()
    wechat_story_images()
    print("Generated LitePark launch assets")
