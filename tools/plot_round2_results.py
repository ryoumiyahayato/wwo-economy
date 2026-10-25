"""Export sampled cloud observations; never calculate or rerun the economy."""
import json
from pathlib import Path
import sys

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt


def main(source, destination):
    report=json.loads(Path(source).read_text())
    macro=next(row['detail'] for row in report['checks'] if row['check']=='365-day global scenarios')
    titles=[('united_states_1900','US wheat',(15,60)),('country_fra','France wheat',(15,60)),('german_empire','Germany coal',(30,90)),('british_isles_1900','British Isles wheat',(45,75))]
    colors={'baseline':'#333333','supply':'#D55E00','demand':'#009E73','transport':'#0072B2','shocks':'#CC79A7'}
    figure, axes=plt.subplots(2,2,figsize=(11.5,7.5),sharex=True)
    for axis,(key,title,window) in zip(axes.flat,titles):
        axis.axvspan(*window,color='#dedede',alpha=.6,zorder=0)
        for case in macro['runs']:
            axis.plot(macro['sample_days'],case['markets'][key]['price_samples'],label=case['scenario'],color=colors[case['scenario']],linewidth=1.6,marker='.',markersize=4,linestyle='--' if case['scenario']=='baseline' else '-')
        axis.set_title(title,loc='left',fontsize=12)
        axis.set_ylabel('Reference price index')
        axis.set_xlabel('Simulation day')
        axis.grid(axis='y',alpha=.2)
        axis.spines[['top','right']].set_visible(False)
        axis.set_xlim(0,365)
    handles,labels=axes[0,0].get_legend_handles_labels()
    figure.legend(handles,labels,loc='upper center',ncol=5,frameon=False,bbox_to_anchor=(.5,.94))
    figure.suptitle('WWO Round 2 - actual 365-day cloud runs',fontsize=17,y=.99)
    figure.text(.5,.01,'12 observed samples; lines connect samples. Independent y scales. Shading: relevant source shock window.\nDevelopment reference model; these curves are not physical deliveries. Source commit: '+report['sha'][:12],ha='center',fontsize=9,color='#444444')
    figure.tight_layout(rect=(0,.06,1,.88))
    figure.savefig(destination,metadata={'Date':None})


if __name__=='__main__':main(sys.argv[1],sys.argv[2])
