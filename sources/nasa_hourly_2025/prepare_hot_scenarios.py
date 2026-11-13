import csv,json,math,shutil
from pathlib import Path
root=Path(__file__).resolve().parents[2]; src=root/'sources'/'nasa_hourly_2025'
archive=root/'sources'/'weather_occ_summer_mean.csv'
if not archive.exists(): shutil.copy2(root/'weather_occ.csv',archive)
with archive.open(newline='',encoding='utf-8-sig') as f:
    reader=csv.DictReader(f);fields=list(reader.fieldnames);old=list(reader)
if 'timestamp_utc' not in fields: fields.insert(fields.index('source'),'timestamp_utc')
def moisture(t,rh,p):
    k=t+273.15
    ps=math.exp(-5800.2206/k+1.3914993-.048640239*k+.000041764768*k*k-1.4452093e-8*k**3+6.5459673*math.log(k))
    pv=rh*ps/100
    return .621945*pv/(p-pv)
chosen={}; selection=[]
for city in ['DAL','BOS','PHX']:
    data=json.loads((src/f'{city}.json').read_text());params=data['properties']['parameter'];valid=[]
    assert data['parameters']['PS']['units']=='kPa'
    assert data['header']['time_standard']=='UTC'
    for stamp,t in params['T2M'].items():
        rh=params['RH2M'][stamp];p=params['PS'][stamp]
        if any(v==data['header']['fill_value'] for v in [t,rh,p]):continue
        assert 0<=rh<=100 and p>0
        valid.append(dict(timestamp_utc=stamp,T=t,RH=rh,pressure=p*1000,w=moisture(t,rh,p*1000)))
    assert len(valid)==2208
    ordered=sorted(valid,key=lambda x:(-x['T'],x['timestamp_utc']))
    hot=ordered[:math.ceil(.1*len(ordered))]
    picks=[('hot_peak',hot[0],'Maximum dry-bulb temperature in June-August 2025')]
    used={hot[0]['timestamp_utc']}
    for name,reverse,description in [('hot_humid',True,'Highest humidity ratio within hottest 10% of hourly records; distinct from peak'),('hot_dry',False,'Lowest humidity ratio within hottest 10% of hourly records; distinct from earlier picks')]:
        eligible=[x for x in hot if x['timestamp_utc'] not in used]
        pick=sorted(eligible,key=lambda x:((-x['w'] if reverse else x['w']),x['timestamp_utc']))[0]
        picks.append((name,pick,description));used.add(pick['timestamp_utc'])
    chosen[city]=picks
    url=(src/f'{city}_request.txt').read_text()
    for name,pick,description in picks:
        selection.append(dict(city=city,scenario=name,**pick,selection_rule=description,hot_subset_min_T=min(x['T'] for x in hot),source=url))
rows=[]
for oldrow in old:
    city=oldrow['venue'].split('_')[0]
    for name,pick,description in chosen[city]:
        row=dict(oldrow)
        row.update(scenario=name,hour='1',dt_hours='1',timestamp_utc=pick['timestamp_utc'],T=str(pick['T']),RH=str(pick['RH']),pressure=str(pick['pressure']))
        row['source']='NASA POWER/MERRA-2 simultaneous hourly gridded meteorology, not a shelter measurement; '+(src/f'{city}_request.txt').read_text()+'; UTC '+pick['timestamp_utc']+'; '+description+'; temperature C, RH %, PS kPa converted to Pa; prior authorized baseline airspeed and mass-exchange estimates held fixed across scenarios; original venue/exposure provenance: sources/weather_occ_summer_mean.csv'
        rows.append(row)
with (root/'weather_occ.csv').open('w',newline='',encoding='utf-8') as f:
    w=csv.DictWriter(f,fieldnames=fields);w.writeheader();w.writerows(rows)
with (src/'selected_scenarios.csv').open('w',newline='',encoding='utf-8') as f:
    w=csv.DictWriter(f,fieldnames=list(selection[0]));w.writeheader();w.writerows(selection)
with (root/'bounds.csv').open(newline='',encoding='utf-8-sig') as f:
    reader=csv.DictReader(f); bfields=list(reader.fieldnames);bounds=[r for r in reader if not r['parameter'].startswith(('weather_occ.','cfg.set_'))]
for i,row in enumerate(rows,1):
    for field in ['T','RH','pressure','v_local','dt_hours']:
        value=float(row[field]);bounds.append(dict(parameter=f'weather_occ.{i}.{field}',lower=str(.95*value),upper=str(1.05*value),source='User-selected +/-5% exploratory perturbation in stored units; not a weather probability model'))
for field,value in [('set_lower',23),('set_upper',26)]:
    bounds.append(dict(parameter='cfg.'+field,lower=str(.95*value),upper=str(1.05*value),source='User-selected comfort threshold; +/-5% policy sensitivity, not an ASHRAE compliance interval'))
with (root/'bounds.csv').open('w',newline='',encoding='utf-8') as f:
    w=csv.DictWriter(f,fieldnames=bfields);w.writeheader();w.writerows(bounds)
for r in selection:print({k:r[k] for k in ['city','scenario','timestamp_utc','T','RH','pressure']})
print('Active cases:',len(rows))
