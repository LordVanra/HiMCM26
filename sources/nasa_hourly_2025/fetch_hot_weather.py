import csv,json,re,urllib.request,urllib.parse,concurrent.futures
from pathlib import Path
root=Path(__file__).resolve().parents[2]
out=root/'sources'/'nasa_hourly_2025';out.mkdir(parents=True,exist_ok=True)
with (root/'weather_occ.csv').open(newline='',encoding='utf-8-sig') as f: rows=list(csv.DictReader(f))
cities={}
for r in rows:
    city=r['venue'].split('_')[0]
    if city not in cities:
        source_url=re.search(r'https://power\.larc\.nasa\.gov/[^; ]+',r['source']).group()
        q=urllib.parse.parse_qs(urllib.parse.urlparse(source_url).query)
        cities[city]=(q['latitude'][0],q['longitude'][0])
def fetch(item):
    city,(lat,lon)=item
    query=urllib.parse.urlencode(dict(parameters='T2M,RH2M,PS',community='SB',latitude=lat,longitude=lon,start='20250601',end='20250831',format='JSON',**{'time-standard':'UTC'}))
    url='https://power.larc.nasa.gov/api/temporal/hourly/point?'+query
    with urllib.request.urlopen(url,timeout=90) as response: raw=response.read()
    data=json.loads(raw)
    assert 'parameter' in data.get('properties',{}),str(data)[:500]
    (out/f'{city}.json').write_bytes(raw)
    (out/f'{city}_request.txt').write_text(url,encoding='utf-8')
    return city,len(data['properties']['parameter']['T2M']),data.get('parameters'),data.get('header')
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
    for result in pool.map(fetch,cities.items()): print(result,flush=True)
