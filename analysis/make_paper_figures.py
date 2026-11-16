"""Export static publication figures from saved results; run at repository root."""
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.patches import Patch
from matplotlib.ticker import MultipleLocator
import pandas as pd

OUT = Path('graphs/paper_figures')
OUT.mkdir(parents=True, exist_ok=True)
o = pd.read_csv('03_decision/result_options.csv')
s = pd.read_csv('04_sensitivity/result_sensitivity_detail.csv')
OPS = ['NONE','A','B','C']
COL = dict(NONE='#66758A', A='#2364AA', B='#25836A', C='#CB592D')
LAB = dict(NONE='No device', A='A · Fan', B='B · Evaporative', C='C · Large evaporative')
SCEN = ['hot_peak','hot_humid','hot_dry']
CITIES = {'DAL': 'Dallas', 'BOS': 'Boston', 'PHX': 'Phoenix'}
VENUE_TYPES = {'BUS': 'Bus', 'RAIL': 'Rail', 'QUAD': 'Courtyard', 'PAV': 'Airport canopy'}
expected = pd.MultiIndex.from_product(
    [pd.read_csv('zones.csv').venue, SCEN, OPS], names=['venue', 'scenario', 'option']
)
actual = pd.MultiIndex.from_frame(o[['venue', 'scenario', 'option']])
assert actual.is_unique and set(actual) == set(expected)
assert o.physical_valid.all() and o.decision_ready.all()
plt.rcParams.update({'font.family':'Arial','font.size':10,'axes.titlesize':11,
    'axes.labelsize':10,'axes.spines.top':False,'axes.spines.right':False,
    'axes.edgecolor':'#B8C1CB','axes.labelcolor':'#26364A','text.color':'#26364A',
    'xtick.color':'#48596D','ytick.color':'#48596D','svg.fonttype':'none',
    'savefig.facecolor':'white','figure.facecolor':'white','axes.facecolor':'white'})

def style(ax):
    ax.set_axisbelow(True)
    ax.grid(axis='x', color='#E6EBF0', linewidth=.7)
    ax.tick_params(length=0, pad=6)

def head(fig,title,subtitle):
    fig.suptitle(title,x=.04,y=.98,ha='left',fontsize=16,fontweight='bold')
    fig.text(.04,.905,subtitle,ha='left',fontsize=10,color='#566579')

def foot(fig,text):
    fig.text(.04,.025,text,ha='left',va='bottom',fontsize=8,color='#566579',linespacing=1.5)

def save(fig,name,data):
    for ext in ['png','svg','pdf']:
        fig.savefig(OUT/f'{name}.{ext}',dpi=300)
    data.to_csv(OUT/f'{name}_data.csv',index=False)
    plt.close(fig)

def dots(ax,g,labels=True):
    ax.axvspan(23,26,color='#EDF3DF',zorder=0)
    ax.axvline(26,color='#8C9B65',ls=(0,(3,3)),lw=.8)
    for y,op in enumerate(OPS):
        value=g.loc[op,'mean_SET']
        ax.scatter(value,y,color=COL[op],s=65,zorder=3,edgecolor='white',linewidth=.8)
        ax.annotate(f'{value:.2f}',(value,y),xytext=(8,0),textcoords='offset points',
                    va='center',fontsize=9,fontweight='bold',color=COL[op])
    ax.set_yticks(range(4),[LAB[x] for x in OPS] if labels else ['']*4)
    ax.set_ylim(3.55,-.55)
    ax.spines['left'].set_visible(False)
    style(ax)

# 1. The main memo figure: matched axes and the explicit comparison band.
b=o[o.venue.eq('BOS_BUS')]
fig,axs=plt.subplots(1,3,figsize=(10.8,4.2))
fig.subplots_adjust(left=.18,right=.97,bottom=.22,top=.75,wspace=.16)
head(fig,'Boston: cooling needs change with the weather',
     'Predicted Standard Effective Temperature (SET); lower values indicate cooler equivalent conditions.')
titles=['Peak temperature','Hot-humid','Hot-dry']
for ax,sc,title in zip(axs,SCEN,titles):
    dots(ax,b[b.scenario.eq(sc)].set_index('option'),ax is axs[0])
    ax.set_xlim(19,33); ax.set_xticks([20,23,26,29,32])
    ax.set_title(title,pad=13,fontweight='bold')
    ax.set_xlabel('SET (°C)')
foot(fig,'Shaded band: chosen 23–26°C SET comparison target; not a heat-safety limit.\nSource: result_options.csv · Boston bus reference case · One-hour scenarios; modeled, not measured shelter performance.')
save(fig,'F1_boston_comfort',b[['scenario','option','mean_SET','coverage_per_person']])

# 2. Resource input versus useful service, one specified scenario.
g=b[b.scenario.eq('hot_peak')].set_index('option')
fig,ax=plt.subplots(figsize=(7.3,4.9))
fig.subplots_adjust(left=.13,right=.96,bottom=.23,top=.76)
head(fig,'More electricity does not guarantee more relief',
     'Boston bus shelter · Peak-temperature scenario · One reference person, one hour')
for op in OPS:
    r=g.loc[op]
    ax.scatter(r.E,r.B_per_person,s=90,color=COL[op],edgecolor='white',zorder=3)
    dx,dy = (9,8) if op!='C' else (-12,12)
    ax.annotate(f'{LAB[op]}\n{r.B_per_person:.2f} degree-hours', (r.E,r.B_per_person),
                xytext=(dx,dy),textcoords='offset points',fontsize=9,
                ha='right' if op=='C' else 'left',color=COL[op],fontweight='bold')
ax.set(xlim=(-.09,2.85),ylim=(-.12,2.7),xlabel='Electricity over one hour (kWh)',
       ylabel='Avoided hot discomfort per person\n(SET degree-hours)')
ax.grid(color='#E6EBF0',lw=.7); ax.set_axisbelow(True)
foot(fig,'Benefit is measured against no device, above the chosen 26°C SET threshold.\nSource: result_options.csv · A delivers the most benefit per kWh; C delivers the most total benefit in this scenario.')
save(fig,'F2_boston_benefit_electricity',g.reset_index()[['option','E','B_per_person','decision_eta']])

# 3. Matched small multiples for the main paper.
p = o[o.scenario.eq('hot_peak')]
fig, axs = plt.subplots(len(CITIES), len(VENUE_TYPES), figsize=(14, 8))
fig.subplots_adjust(left=.14, right=.97, bottom=.12, top=.84, wspace=.28, hspace=.55)
head(fig, 'Peak-hour thermal comfort across 12 venues',
     'Predicted SET for four cooling options during each city’s selected peak-temperature hour.')
limits = (min(22, p.mean_SET.min() - 1), max(37, p.mean_SET.max() + 2.5))
for row, (city, city_name) in zip(axs, CITIES.items()):
    for ax, (kind, kind_name) in zip(row, VENUE_TYPES.items()):
        venue = f'{city}_{kind}'
        dots(ax, p[p.venue.eq(venue)].set_index('option'), kind == 'BUS')
        ax.set_xlim(*limits)
        ax.set_xticks([23, 26, 29, 32, 35])
        ax.set_title(f'{city_name} · {kind_name}', loc='left', fontweight='bold')
        ax.set_xlabel('SET (°C)')
foot(fig,'Shaded band: chosen 23–26°C SET comparison target; not a safety classification.\nSource: result_options.csv · Peak hours differ by city · Reference exposure and estimated airflow; modeled results.')
save(fig,'F3_all_venues_peak_comfort',p[['venue','option','mean_SET','mean_SET_drop']])

# 4. Separate resource axes prevent mixing units or hiding water behind a score.
g=b[b.scenario.eq('hot_peak')&b.option.ne('NONE')].set_index('option').loc[['A','B','C']]
fig,axs=plt.subplots(1,3,figsize=(10.8,4.5))
fig.subplots_adjust(left=.07,right=.97,bottom=.24,top=.74,wspace=.4)
head(fig,'The larger cooler carries a larger resource commitment',
     'Boston bus shelter · Peak-temperature scenario · Reference equipment prices')
for ax,field,title,fmt in zip(axs,['E','water_kg','purchase_cost'],
    ['Electricity per hour (kWh)','Evaporated water per hour (kg)','Purchase cost (USD)'],
    ['{:.2f}','{:.1f}','${:,.0f}']):
    vals=g[field]
    bars=ax.bar(['A','B','C'],vals,color=[COL[x] for x in g.index],width=.55,zorder=3)
    ax.set_ylim(0,max(vals)*1.25)
    ax.set_title(title,pad=13,fontweight='bold',fontsize=10)
    ax.grid(axis='y',color='#E6EBF0',lw=.7); ax.set_axisbelow(True)
    for bar,value in zip(bars,vals):
        ax.text(bar.get_x()+bar.get_width()/2,value+max(vals)*.035,fmt.format(value),
                ha='center',va='bottom',fontsize=10,fontweight='bold')
    ax.tick_params(length=0);ax.spines['left'].set_visible(False)
foot(fig,'A = fan; B = evaporative cooler; C = larger evaporative cooler. No-device inputs are zero.\nSource: result_options.csv · Water excludes flushing/cleaning; prices exclude installation, tax and maintenance.')
save(fig,'F4_boston_resources',g.reset_index()[['option','E','water_kg','purchase_cost']])

# 5. A true one-parameter response: keep scenario fixed when calculating ranges.
weather = pd.read_csv('weather_occ.csv')
weather_row, = weather.index[weather.venue.eq('BOS_BUS') & weather.scenario.eq('hot_humid')]
baseline_temperature = weather.loc[weather_row, 'T']
parameter = f'weather_occ.{weather_row + 1}.T'
d = s[s.parameter.eq(parameter) & s.venue.eq('BOS_BUS') & s.scenario.eq('hot_humid')].copy()
assert len(d)==20 and not d.duplicated(['value','option']).any()
fig,ax=plt.subplots(figsize=(7.5,4.9))
fig.subplots_adjust(left=.11,right=.96,bottom=.25,top=.75)
head(fig,'Boston comfort is sensitive to outdoor temperature',
     'Hot-humid scenario · Relative humidity and other inputs held fixed')
ax.axhspan(23,26,color='#EDF3DF',zorder=0)
ax.axvline(baseline_temperature,color='#9AA5B1',ls='--',lw=1)
for op in OPS:
    a=d[d.option.eq(op)].sort_values('value')
    ax.plot(a.value,a.mean_SET,marker='o',markersize=4,color=COL[op],label=LAB[op],lw=2)
ax.set(xlabel='Outdoor air temperature (°C)',ylabel='Predicted SET (°C)',ylim=(21.8,30.5))
ax.grid(color='#E6EBF0',lw=.7); ax.set_axisbelow(True)
ax.legend(loc='upper left',frameon=False,fontsize=9,ncol=2)
foot(fig,f'Dashed line: baseline {baseline_temperature:.2f}°C. Shaded band: chosen comparison target.\nSource: result_sensitivity_detail.csv · Five exploratory ±5% temperature settings; not confidence intervals.')
save(fig,'F5_boston_temperature_sensitivity',d[['value','option','mean_SET','L','chosen_option']].sort_values(['option','value']))

print(f'Exported five figures as PNG (300 dpi), SVG, PDF and plotted-data CSV to {OUT.resolve()}')
