from pathlib import Path
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

OUT = Path('graphs/paper_figures')
d = pd.read_csv(OUT / 'F3_all_venues_peak_comfort_data.csv')
cities = ['Boston', 'Dallas', 'Phoenix']
venues = ['BOS_BUS', 'DAL_BUS', 'PHX_BUS']
colors = ['#2364AA', '#CB592D']
plt.rcParams.update({'font.family':'Arial','font.size':11,'axes.spines.top':False,'axes.spines.right':False,'axes.edgecolor':'#B8C1CB','text.color':'#26364A','axes.labelcolor':'#26364A','xtick.color':'#48596D','ytick.color':'#48596D','svg.fonttype':'none','savefig.facecolor':'white'})
rows=[]
for city,venue in zip(cities,venues):
    for op,power,label in [('A',.25,'Fan'),('C',2.5,'Larger evaporative cooler')]:
        drop=float(d.loc[(d.venue==venue)&(d.option==op),'mean_SET_drop'].iloc[0])
        rows.append(dict(city=city,device=label,felt_cooling_C=drop,electricity_kWh=power,felt_cooling_per_kWh=drop/power))
a=pd.DataFrame(rows)
x=np.arange(3)

def finish(fig,ax,name):
    ax.set_xticks(x,cities)
    ax.set_axisbelow(True)
    ax.grid(axis='y',color='#E6EBF0',linewidth=.8)
    ax.tick_params(length=0,pad=8)
    fig.tight_layout()
    for ext in ['png','svg','pdf']:
        fig.savefig(OUT/f'{name}.{ext}',dpi=300)
    plt.close(fig)

fig,ax=plt.subplots(figsize=(8,5))
for label,color,offset,power in [('Fan',colors[0],-.18,.25),('Larger evaporative cooler',colors[1],.18,2.5)]:
    vals=a[a.device==label].felt_cooling_C.to_numpy()
    ax.bar(x+offset,vals,width=.32,color=color,label=f'{label} ({power:g} kWh)',zorder=3)
    for xi,v in zip(x+offset,vals):
        ax.annotate(f'{v:.2f}',(xi,v),xytext=(0,12),textcoords='offset points',ha='center',color=color,fontweight='bold')
ax.set_title('Felt cooling over one hour',fontsize=17,fontweight='bold',pad=20,loc='center')
ax.set_ylabel('Felt cooling (SET reduction, °C)')
ax.yaxis.label.set_size(18)
ax.yaxis.labelpad = 14
ax.set_xlabel('City',fontsize=18,labelpad=12)
ax.set_ylim(0,2.9)
ax.set_xlim(-.5,2.5)
ax.legend(loc='upper center',frameon=False,ncol=2,fontsize=10)
finish(fig,ax,'F6_three_cities_felt_cooling')

fig,ax=plt.subplots(figsize=(8,5))
for label,color,offset in [('Fan',colors[0],-.18),('Larger evaporative cooler',colors[1],.18)]:
    vals=a[a.device==label].felt_cooling_per_kWh.to_numpy()
    bars=ax.bar(x+offset,vals,width=.32,color=color,label=label,zorder=3)
    ax.bar_label(bars,labels=[f'{v:.2f}' for v in vals],padding=6,color=color,fontweight='bold')
ax.set_title('Felt cooling per kWh',fontsize=17,fontweight='bold',pad=20,loc='center')
ax.set_ylabel('SET reduction per kWh (°C/kWh)')
ax.yaxis.label.set_size(18)
ax.yaxis.labelpad = 14
ax.set_xlabel('City',fontsize=18,labelpad=12)
ax.set_ylim(0,8.5)
ax.legend(loc='upper center',frameon=False,ncol=2,fontsize=10)
finish(fig,ax,'F7_three_cities_cooling_per_kWh')
a.to_csv(OUT/'F6_F7_three_cities_data.csv',index=False)
