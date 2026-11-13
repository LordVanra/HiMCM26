"""Review saved model results; run from the repository root."""
import json
from pathlib import Path
import pandas as pd

o = pd.read_csv('03_decision/result_options.csv')
z = pd.read_csv('01_physics/result_zone_conditions.csv')
s = pd.read_csv('04_sensitivity/result_sensitivity_detail.csv')
m = pd.read_csv('01_physics/result_mass_balance.csv')
assert len(o) == 72 and not o.duplicated(['venue','scenario','option']).any()
assert o.physical_valid.all() and o.decision_ready.all()
base = o[o.option.eq('NONE')].set_index(['venue','scenario'])
errors = []
for r in o.itertuples():
    b = base.loc[(r.venue,r.scenario)]
    errors += [abs(r.L_per_person - max(0,r.mean_SET-26)),
               abs(r.B_per_person - (b.L_per_person-r.L_per_person))]
    if r.E > 0:
        errors.append(abs(r.decision_eta-r.B_per_person/r.E))
assert max(errors) < 1e-9
def records(df):
    return json.loads(df.to_json(orient='records', double_precision=5))
summary = dict(rows=len(o), scenarios_per_venue=3,
    all_physical_valid=bool(o.physical_valid.all()),
    all_decision_ready=bool(o.decision_ready.all()),
    max_formula_error=max(errors), mass_balance_max=float(m.mass_residual_kg_s.abs().max()),
    peak=records(o[o.scenario.eq('hot_peak')][['venue','option','mean_SET','mean_SET_drop','E','water_kg']]),
    ranges=records(o.groupby('option').agg(SET_drop_min=('mean_SET_drop','min'),SET_drop_max=('mean_SET_drop','max'),water_min=('water_kg','min'),water_max=('water_kg','max'),eta_min=('decision_eta','min'),eta_max=('decision_eta','max')).reset_index()),
    coverage=records(o.groupby(['venue','option']).agg(in_band_cases=('coverage_per_person','sum')).reset_index()),
    best_efficiency=[],
    b_vs_a=records(o.pivot(index=['venue','scenario'],columns='option',values='mean_SET').assign(B_minus_A=lambda d:d.B-d.A).reset_index()[['venue','scenario','B_minus_A']]),
    sensitivity_rows=len(s), sensitivity_parameters=s.parameter.nunique(),
    sensitivity_choices=records(s[['parameter','value','venue','chosen_option','baseline_choice']].drop_duplicates().groupby(['venue','chosen_option']).size().reset_index(name='cases')))
for (v,c),g in o[o.E.gt(0)].groupby(['venue','scenario']):
    best=g[g.decision_eta.ge(g.decision_eta.max()-1e-6)]
    summary['best_efficiency'].append(dict(venue=v,scenario=c,options=';'.join(best.option)))
rank=s.groupby(['venue','scenario','parameter','option']).mean_SET.agg(['min','max'])
rank['swing']=rank['max']-rank['min']
summary['largest_SET_sensitivity']=records(rank.reset_index().sort_values('swing',ascending=False).groupby('venue').head(4))
Path('analysis/results_review.json').write_text(json.dumps(summary,indent=2))
print(json.dumps(summary,indent=2))
