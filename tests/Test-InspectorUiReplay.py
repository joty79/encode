"""Replay actual inspector ANSI frames on one resized virtual terminal; optional PNG preview."""
import json, pathlib, re, sys
import pyte
from wcwidth import wcswidth

class Screen(pyte.Screen):
    def __init__(self, columns, lines):
        super().__init__(columns, lines)
        self.scrolls=0
    def index(self):
        at_bottom=self.cursor.y==(self.lines-1 if self.margins is None else self.margins.bottom)
        super().index()
        if at_bottom: self.scrolls+=1

manifest=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8-sig'))
screen=Screen(manifest[0]['width'],manifest[0]['height'])
stream=pyte.Stream(screen)
ansi=re.compile(r'\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1b\\))')
previous=None
for item in manifest:
    screen.resize(lines=item['height'],columns=item['width'])
    payload=pathlib.Path(item['path']).read_text(encoding='utf-8').replace('\n','\r\n')
    for line in ansi.sub('',payload).splitlines():
        assert wcswidth(line)<item['width'], f"overflow at state {item['state']}: {line}"
    before=screen.scrolls
    stream.feed(payload)
    assert screen.scrolls==before, f"scroll at state {item['state']}"
    display='\n'.join(screen.display)
    marker=f"STATE-{item['state']}"
    assert display.count('MEDIA INFO')==1, 'missing/duplicate header'
    assert display.count(marker)==1, 'missing/duplicate current state'
    assert previous is None or not re.search(re.escape(previous)+r'(?!\d)',display), 'stale previous frame'
    previous=marker
    if item['state']==2 and len(sys.argv)>2:
        from PIL import Image, ImageDraw, ImageFont
        font=ImageFont.truetype(r'C:\Windows\Fonts\consola.ttf',18)
        emoji=ImageFont.truetype(r'C:\Windows\Fonts\seguiemj.ttf',18)
        cell=font.getlength('M'); height=25
        image=Image.new('RGB',(round(screen.columns*cell+24),screen.lines*height+16),'#0c0c0c')
        draw=ImageDraw.Draw(image)
        palette={'default':'#cccccc','black':'#0c0c0c','brightblack':'#898989','white':'#cccccc','brightwhite':'#f2f2f2','cyan':'#3a9696','brightcyan':'#61d6d6','blue':'#0037da','brightblue':'#3b78ff','yellow':'#c19c00','brightyellow':'#f9e287','red':'#c50f1f','brightred':'#f77676','green':'#13a10e','brightgreen':'#87d787','magenta':'#881798','brightmagenta':'#cc99ff'}
        def color(value, default):
            if value in palette: return palette[value]
            if len(value)==6: return '#'+value
            return default
        for y in range(screen.lines):
            for x in range(screen.columns):
                char=screen.buffer[y][x]
                if not char.data: continue
                left=12+x*cell; top=8+y*height
                if char.bg!='default': draw.rectangle((left,top,left+cell*max(1,wcswidth(char.data)),top+height),fill=color(char.bg,'#0c0c0c'))
                face=emoji if any(ord(c)>0xffff for c in char.data) else font
                draw.text((left,top),char.data,font=face,fill=color(char.fg,'#cccccc'))
        image.save(sys.argv[2])
print(f'PASS: {len(manifest)} live-screen transitions; zero wraps, scrolls, duplicate headers or stale frames.')
