"""Download only selected CC0 texture maps and the OFL Chinese interface font."""
import urllib.request,urllib.parse,json,time,hashlib,concurrent.futures
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets'/'textures'/'photographic';OUT.mkdir(exist_ok=True)
IDS=['castle_brick_02_white','castle_brick_01','painted_plaster_wall','herringbone_parquet','old_wood_floor','marble_01','quatrefoil_jacquard_fabric','fabric_leather_01','cobblestone_floor_02','rock_boulder_cracked']
def fetch(url):
    for attempt in range(5):
        try:
            req=urllib.request.Request(url,headers={'User-Agent':'EuropeTravelLocalProject/2.0'})
            return urllib.request.urlopen(req,timeout=45).read()
        except Exception:
            if attempt==4:raise
            time.sleep(1+attempt)
def asset(key):
    cache=OUT/(key+'_files.json')
    if cache.exists():meta=json.loads(cache.read_text())
    else:meta=json.loads(fetch('https://api.polyhaven.com/files/'+key));cache.write_text(json.dumps(meta),encoding='utf-8')
    maps={}
    aliases={'base':['diff','diffuse','Diffuse','color','albedo'],'normal':['nor_gl','normal'],'rough':['rough','roughness','Rough']}
    for kind,options in aliases.items():
        entry=next((meta[k] for k in options if k in meta),None)
        if entry is None:
            print('MAP_KEYS',key,kind,list(meta),flush=True);continue
        choices=entry.get('1k') or entry.get('2k')
        if not choices:continue
        ext='jpg' if 'jpg' in choices else 'png';spec=choices[ext]
        dest=OUT/(key+'_'+kind+'.'+ext)
        if not dest.exists():dest.write_bytes(fetch(spec['url']))
        assert dest.stat().st_size>1000
        maps[kind]=str(dest.relative_to(ROOT).as_posix())
    result={'asset':key,'license':'CC0','source':'https://polyhaven.com/a/'+key,'maps':maps}
    print('TEXTURE',key,maps,flush=True);return result
results=[]
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    for f in concurrent.futures.as_completed([pool.submit(asset,k) for k in IDS]):
        try:results.append(f.result())
        except Exception as e:print('DOWNLOAD_ERROR',repr(e),flush=True)
(OUT/'sources.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
font=ROOT/'assets'/'fonts'/'NotoSansSC.ttf'
if not font.exists():font.write_bytes(fetch('https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf'))
(font.parent/'OFL.txt').write_bytes(fetch('https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/OFL.txt'))
print('DONE',len(results),'texture sets; font',font.stat().st_size,flush=True)
