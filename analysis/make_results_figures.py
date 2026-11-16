"""Export compact results figures from the saved model and radar data."""
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap
from matplotlib.lines import Line2D
import numpy as np
import pandas as pd


OUT = Path("graphs/paper_figures")
OPTIONS = {"NONE": "No device", "A": "A · Fan", "B": "B · Evaporative",
           "C": "C · Larger evaporative"}
COLORS = {"NONE": "#66758A", "A": "#2364AA", "B": "#25836A", "C": "#CB592D"}
CITIES = {"DAL": "Dallas", "BOS": "Boston", "PHX": "Phoenix"}
PLACES = {"BUS": "Bus", "RAIL": "Rail", "QUAD": "Courtyard", "PAV": "Airport canopy"}
SCENARIOS = {"hot_peak": ("Peak", "o"), "hot_humid": ("Hot-humid", "s"),
             "hot_dry": ("Hot-dry", "^")}
INK = "#26364A"
MUTED = "#566579"

plt.rcParams.update({
    "font.family": "Arial", "font.size": 10, "text.color": INK,
    "axes.labelcolor": INK, "xtick.color": MUTED, "ytick.color": INK,
    "axes.spines.top": False, "axes.spines.right": False, "svg.fonttype": "none",
})


def heading(fig, title, subtitle):
    fig.text(.045, .96, title, size=17, weight="bold", va="top")
    fig.text(.045, .875, subtitle, size=10, color=MUTED, va="top")


def save(fig, stem, data):
    for extension in ("pdf", "png", "svg"):
        fig.savefig(OUT / f"{stem}.{extension}", dpi=300, facecolor="white")
    data.to_csv(OUT / f"{stem}_data.csv", index=False)
    plt.close(fig)


def efficiency_figure(options):
    data = options.loc[options.option.ne("NONE"),
                       ["venue", "scenario", "option", "mean_SET_drop", "E", "purchase_cost"]].copy()
    data["SET_drop_per_kWh"] = data.mean_SET_drop / data.E
    data["SET_drop_per_1000_USD"] = 1000 * data.mean_SET_drop / data.purchase_cost
    counts = data.groupby("option").size()
    assert counts.to_dict() == {"A": 36, "B": 36, "C": 36}
    assert not data.duplicated(["venue", "scenario", "option"]).any()
    leaders = {}
    fig, axes = plt.subplots(1, 2, figsize=(10.7, 4.7), sharey=True)
    fig.subplots_adjust(left=.19, right=.97, top=.72, bottom=.24, wspace=.24)
    heading(fig, "Cooling efficiency across 36 venue–weather cases",
            "Each point shows one venue and weather scenario. Cooling is the SET reduction from no device.")

    for ax, field, title, unit in zip(
        axes, ["SET_drop_per_kWh", "SET_drop_per_1000_USD"],
        ["Per unit of electricity", "Per unit of purchase cost"],
        ["SET reduction (°C) per kWh", "SET reduction (°C) per $1,000"],
    ):
        winners = data.loc[data.groupby(["venue", "scenario"])[field].idxmax()]
        leaders[field] = winners.option.value_counts()
        for y, option in enumerate(("A", "B", "C")):
            for offset, (scenario, (_, marker)) in zip((-.22, 0, .22), SCENARIOS.items()):
                group = data[data.option.eq(option) & data.scenario.eq(scenario)].sort_values(field)
                offsets = offset + np.resize([0, -.045, .045, -.085, .085], len(group))
                ax.scatter(group[field], y + offsets, c=COLORS[option], marker=marker, s=30,
                           alpha=.65, edgecolors="white", linewidths=.35, zorder=3)
        ax.set_title(title, loc="left", weight="bold", pad=10)
        ax.set(xlabel=unit, xlim=(0, data[field].max() * 1.07), ylim=(2.55, -.55))
        ax.set_yticks(range(3), [OPTIONS[op] for op in ("A", "B", "C")])
        ax.grid(axis="x", color="#E6EBF0")
        ax.tick_params(axis="both", length=0, pad=7)
        ax.spines["left"].set_visible(False)
        for y in (.5, 1.5):
            ax.axhline(y, color="#E6EBF0", lw=.8)

    handles = [Line2D([0], [0], marker=marker, color=MUTED, linestyle="none", label=label)
               for label, marker in SCENARIOS.values()]
    fig.legend(handles=handles, loc="lower center", bbox_to_anchor=(.57, .09),
               ncols=3, frameon=False)
    energy = leaders["SET_drop_per_kWh"]
    cost = leaders["SET_drop_per_1000_USD"]
    fig.text(.045, .04, f"Cases led by A: {energy.get('A', 0)}/36 per kWh and "
             f"{cost.get('A', 0)}/36 per $1,000. C led the other {cost.get('C', 0)} purchase-cost cases.",
             color=MUTED, size=9)
    save(fig, "F6_efficiency_all_cases", data)


def regret_figure(recommendations):
    venues = [f"{city}_{place}" for city in CITIES for place in PLACES]
    data = recommendations[["venue", "option", "max_regret", "chosen"]]
    values = data.pivot(index="venue", columns="option", values="max_regret").loc[venues, list(OPTIONS)]
    chosen = data.pivot(index="venue", columns="option", values="chosen").loc[venues, list(OPTIONS)]
    assert np.isfinite(values).all().all()
    assert (chosen.sum(axis=1) == 1).all()
    assert np.allclose(values.where(chosen).min(axis=1), values.min(axis=1))
    fig, ax = plt.subplots(figsize=(8.4, 6.1))
    fig.subplots_adjust(left=.26, right=.89, top=.76, bottom=.10)
    heading(fig, "Maximum regret by venue and cooling option",
            "Each cell shows the option’s largest shortfall from the best feasible option across three weather cases.")
    cmap = LinearSegmentedColormap.from_list("regret", ["#F5F8FA", "#9BC0D8", "#24557C"])
    vmax = values.to_numpy().max()
    mesh = ax.imshow(values, cmap=cmap, vmin=0, vmax=vmax, aspect="auto")
    ax.set_xticks(range(4), ["No device", "A · Fan", "B · Evaporative", "C · Larger\nevaporative"])
    ax.set_yticks(range(12), [f"{CITIES[city]} · {PLACES[place]}"
                             for city in CITIES for place in PLACES])
    ax.xaxis.tick_top()
    ax.tick_params(length=0, pad=8)
    for y, (_, row) in enumerate(values.iterrows()):
        for x, (option, value) in enumerate(row.items()):
            winner = chosen.iloc[y][option]
            if winner:
                ax.add_patch(plt.Rectangle((x - .49, y - .49), .98, .98, facecolor="#DFF0E8",
                                           edgecolor="white", linewidth=.7))
            ax.text(x, y, f"{value:.2f}", ha="center", va="center",
                    color="white" if value > .62 * vmax else INK,
                    weight="bold" if winner else "normal")
    for y in (3.5, 7.5):
        ax.axhline(y, color="white", lw=2.5)
    ax.spines[["left", "bottom"]].set_visible(False)
    fig.colorbar(mesh, ax=ax, fraction=.055, pad=.045, label="SET degree-hours")
    fig.text(.045, .033, "Green cells mark the minimax choice for each venue.", color=MUTED, size=9)
    save(fig, "F7_maximum_regret_all_venues", data)


def radar_figure(radar):
    data = radar.loc[radar.venue.eq("BOS_BUS"),
                     ["venue", "option", "axis", "metric", "raw", "scaled", "axis_maximum"]].copy()
    axes = data[["axis", "metric", "axis_maximum"]].drop_duplicates().sort_values("axis")
    profiles = data.pivot(index="axis", columns="option", values="scaled").loc[axes.axis, list(OPTIONS)]
    assert len(axes) == 4 and profiles.notna().all().all()
    assert np.allclose(data.scaled, data.raw / data.axis_maximum)
    angles = np.linspace(0, 2 * np.pi, len(axes), endpoint=False)
    closed = np.r_[angles, angles[0]]
    fig, ax = plt.subplots(figsize=(7.5, 5.8), subplot_kw={"projection": "polar"})
    fig.subplots_adjust(left=.16, right=.84, top=.69, bottom=.25)
    heading(fig, "Minimax radar for the Boston bus shelter",
            "Maximum regret and worst-case resource use across the three modeled weather scenarios.")
    ax.set_theta_zero_location("N")
    ax.set_theta_direction(-1)
    labels = ["Maximum regret", "Purchase\nprice", "Electricity", "Evaporated\nwater"]
    ax.set_xticks(angles, labels)
    ax.tick_params(axis="x", pad=20)
    ax.set(ylim=(0, 1), yticks=[.25, .5, .75, 1], yticklabels=["", "", "", ""])
    ax.grid(color="#C9D4DF", lw=.75)
    ax.spines["polar"].set_color("#A5B3C1")
    for option, values in profiles.items():
        radius = np.r_[values, values.iloc[0]]
        ax.plot(closed, radius, color=COLORS[option], marker="o", markersize=4,
                linewidth=1.8, linestyle="--" if option == "NONE" else "-", label=OPTIONS[option])
        if option == "C":
            ax.fill(closed, radius, color=COLORS[option], alpha=.09)
    handles, labels = ax.get_legend_handles_labels()
    fig.legend(handles, labels, loc="lower center", bbox_to_anchor=(.5, .095), ncols=4, frameon=False)
    fig.text(.045, .04,
             "Each axis uses the original D07 gallery scale. The center is zero.\n"
             "Minimax selection uses the maximum-regret axis. Cost, electricity and water show the trade-off.",
             color=MUTED, size=9)
    save(fig, "F8_boston_minimax_radar", data)


def efficiency_case_map(options):
    data = options.loc[options.option.ne("NONE"),
                       ["venue", "scenario", "option", "mean_SET_drop", "purchase_cost"]].copy()
    data["efficiency"] = 1000 * data.mean_SET_drop / data.purchase_cost
    ranked = data.sort_values("efficiency", ascending=False)
    winners = ranked.drop_duplicates(["venue", "scenario"])
    grid = winners.set_index(["venue", "scenario"])
    fig, ax = plt.subplots(figsize=(8.2, 6.3))
    fig.subplots_adjust(left=.27, right=.95, top=.75, bottom=.15)
    heading(fig, "Which device delivers the most cooling per dollar?",
            "Each cell identifies the winner and its SET reduction per $1,000 of equipment price.")
    for y, (city, place) in enumerate((c, p) for c in CITIES for p in PLACES):
        for x, scenario in enumerate(SCENARIOS):
            row = grid.loc[(f"{city}_{place}", scenario)]
            ax.add_patch(plt.Rectangle((x - .48, y - .46), .96, .92,
                                       facecolor=COLORS[row.option], alpha=.16))
            ax.text(x, y, f"{row.option}   {row.efficiency:.2f}", ha="center", va="center",
                    color=COLORS[row.option], weight="bold")
    ax.set(xlim=(-.5, 2.5), ylim=(11.5, -.5))
    ax.set_xticks(range(3), [item[0] for item in SCENARIOS.values()])
    ax.set_yticks(range(12), [f"{city} · {place}" for city in CITIES.values() for place in PLACES.values()])
    ax.xaxis.tick_top()
    ax.tick_params(length=0, pad=9)
    for y in (3.5, 7.5):
        ax.axhline(y, color="#B8C6D1", lw=.9)
    ax.spines[["bottom", "left"]].set_visible(False)
    fig.text(.27, .073, "A · Fan                  C · Larger evaporative", size=10)
    save(fig, "F9_purchase_efficiency_winners", data)


def energy_tradeoff(options):
    data = options.loc[options.option.ne("NONE") & options.scenario.eq("hot_peak"),
                       ["venue", "option", "mean_SET_drop", "E"]].copy()
    fig, ax = plt.subplots(figsize=(8.7, 5.1))
    fig.subplots_adjust(left=.12, right=.95, top=.74, bottom=.22)
    heading(fig, "Peak-hour cooling and electricity by device",
            "Each dot is one venue. Electricity stays fixed for a device while delivered cooling varies.")
    offsets = {"DAL": -.06, "BOS": 0, "PHX": .06}
    markers = {"DAL": "o", "BOS": "s", "PHX": "^"}
    for (option, city), group in data.groupby(["option", data.venue.str[:3]]):
        ax.scatter(group.E + offsets[city], group.mean_SET_drop,
                   color=COLORS[option], marker=markers[city], s=56, alpha=.82,
                   edgecolor="white", linewidth=.6)
    ax.set_xticks([.25, 1.2, 2.5], ["A · Fan\n0.25", "B · Evaporative\n1.20", "C · Larger evaporative\n2.50"])
    ax.set(xlim=(-.01, 2.78), ylim=(0, None),
           xlabel="Electricity per modeled hour (kWh)", ylabel="SET reduction from no device (°C)")
    ax.grid(axis="y", color="#E6EBF0")
    ax.set_axisbelow(True)
    ax.tick_params(length=0, pad=7)
    handles = [Line2D([0], [0], marker=markers[city], color=MUTED, linestyle="none", label=name)
               for city, name in CITIES.items()]
    fig.legend(handles=handles, loc="lower center", bbox_to_anchor=(.55, .025), ncols=3, frameon=False)
    fig.text(.045, .025, "City markers are offset slightly for legibility.", color=MUTED, size=8)
    save(fig, "F10_peak_cooling_electricity", data)


def scaling_response(scaling):
    data = scaling.loc[scaling.cooler_limit.eq("saturation_limit") & scaling.option.ne("NONE"),
                       ["venue", "option", "exchange_multiplier", "set_drop_per_kwh"]]
    fig, panels = plt.subplots(1, 3, figsize=(10.8, 4.8), sharey=True)
    fig.subplots_adjust(left=.09, right=.97, top=.73, bottom=.27, wspace=.15)
    heading(fig, "Ventilation changes modeled cooling efficiency",
            "Courtyards and airport canopies under the archived summer-mean reference conditions.")
    for ax, (city, label) in zip(panels, CITIES.items()):
        for (venue, option), group in data[data.venue.str.startswith(city)].groupby(["venue", "option"]):
            group = group.sort_values("exchange_multiplier")
            canopy = venue.endswith("PAV")
            ax.plot(group.exchange_multiplier, group.set_drop_per_kwh, color=COLORS[option],
                    linestyle="--" if canopy else "-", marker="s" if canopy else "o",
                    markersize=4, linewidth=1.55)
        ax.set_title(label, loc="left", weight="bold")
        ax.set_xticks([1, 2, 4], ["1×", "2×", "4×"])
        ax.set_yscale("log")
        ax.set_ylim(data.set_drop_per_kwh.min() * .8, data.set_drop_per_kwh.max() * 1.25)
        ax.set_yticks([.2, .5, 1, 2, 5, 10], ["0.2", "0.5", "1", "2", "5", "10"])
        ax.grid(axis="y", color="#E6EBF0")
        ax.tick_params(length=0, pad=5)
    panels[0].set_ylabel("SET reduction (°C) per kWh · log scale")
    fig.supxlabel("Outdoor air exchange relative to the reference rate", y=.16, size=10)
    devices = [Line2D([0], [0], color=COLORS[op], label=OPTIONS[op]) for op in ("A", "B", "C")]
    sites = [Line2D([0], [0], color=MUTED, marker="o", label="Courtyard"),
             Line2D([0], [0], color=MUTED, marker="s", linestyle="--", label="Airport canopy")]
    fig.legend(handles=devices + sites, loc="lower center", bbox_to_anchor=(.54, .045),
               ncols=5, frameon=False)
    fig.text(.045, .025, "The sweep holds fan airspeed at the passenger fixed.", color=MUTED, size=8)
    save(fig, "F11_ventilation_efficiency", data)


def efficiency_head_to_head(options):
    active = options.loc[options.option.ne("NONE"), ["venue", "scenario", "option", "mean_SET_drop", "E"]].copy()
    active["efficiency"] = active.mean_SET_drop / active.E
    data = active.pivot(index=["venue", "scenario"], columns="option", values="efficiency").reset_index()
    data["fan_advantage"] = data.A / data[["B", "C"]].max(axis=1)
    fig, ax = plt.subplots(figsize=(8.9, 6))
    fig.subplots_adjust(left=.24, right=.95, top=.76, bottom=.17)
    heading(fig, "How much more cooling per kWh does the fan deliver?",
            "Fan efficiency divided by the efficiency of the better evaporative cooler in the same case.")
    venues = [f"{c}_{p}" for c in CITIES for p in PLACES]
    for offset, (scenario, (label, marker)) in zip((-.2, 0, .2), SCENARIOS.items()):
        cases = data[data.scenario.eq(scenario)].set_index("venue").loc[venues]
        ax.scatter(cases.fan_advantage, np.arange(len(venues)) + offset,
                   color=COLORS["A"], marker=marker, s=43, alpha=.78, label=label, zorder=3)
    ax.axvline(1, color=MUTED, lw=1, linestyle="--")
    ax.set(ylim=(11.6, -.6), xlabel="Fan advantage in SET reduction per kWh (×)")
    ax.set_yticks(range(12), [f"{c} · {p}" for c in CITIES.values() for p in PLACES.values()])
    ax.tick_params(length=0, pad=7)
    ax.grid(axis="x", color="#E6EBF0")
    for y in (3.5, 7.5):
        ax.axhline(y, color="#C9D4DF", lw=.8)
    ax.spines["left"].set_visible(False)
    handles, labels = ax.get_legend_handles_labels()
    fig.legend(handles, labels, loc="lower center", bbox_to_anchor=(.59, .045), ncols=3, frameon=False)
    save(fig, "F12_fan_efficiency_advantage", data)


def regret_cost_tradeoff(recommendations, options):
    prices = options[["venue", "option", "purchase_cost"]].drop_duplicates()
    data = recommendations[["venue", "option", "max_regret", "chosen"]].merge(
        prices, on=["venue", "option"], validate="one_to_one"
    )
    data = data[data.venue.str.endswith("_BUS")]
    fig, panels = plt.subplots(1, 3, figsize=(10.8, 4.6), sharex=True, sharey=True)
    fig.subplots_adjust(left=.10, right=.96, top=.73, bottom=.24, wspace=.15)
    heading(fig, "Purchase price and worst-case comfort regret",
            "Bus shelters in each city. The line connects options on the cost–regret frontier.")
    for ax, (city, label) in zip(panels, CITIES.items()):
        group = data[data.venue.eq(f"{city}_BUS")].sort_values("purchase_cost")
        frontier = group[group.max_regret.lt(group.max_regret.cummin().shift(fill_value=np.inf))]
        ax.plot(frontier.purchase_cost, frontier.max_regret, color="#A5B3C1", linewidth=1.5)
        for row in group.itertuples():
            ax.scatter(row.purchase_cost, row.max_regret, s=68, color=COLORS[row.option],
                       edgecolor="white", linewidth=.7, zorder=3)
            ax.annotate("None" if row.option == "NONE" else row.option,
                        (row.purchase_cost, row.max_regret), xytext=(0, 9),
                        textcoords="offset points", ha="center", color=COLORS[row.option], weight="bold")
        ax.set_title(label, loc="left", weight="bold")
        ax.set(xlim=(-450, 5550), ylim=(-.15, 3), xticks=[0, 2500, 5000])
        ax.set_xticklabels(["$0", "$2,500", "$5,000"])
        ax.grid(axis="y", color="#E6EBF0")
        ax.set_axisbelow(True)
        ax.tick_params(length=0, pad=5)
    panels[0].set_ylabel("Maximum regret (SET degree-hours)")
    fig.supxlabel("Equipment purchase price", y=.105, size=10)
    fig.text(.045, .032, "A · Fan     B · Evaporative     C · Larger evaporative", color=MUTED, size=9)
    save(fig, "F13_bus_cost_regret_frontier", data)


def sensitivity_switches(switches, weather):
    data = switches.copy()
    weather_rows = weather.reset_index(drop=True)
    data["baseline"] = [
        26 if parameter == "cfg.set_upper" else weather_rows.loc[int(parameter.split(".")[1]) - 1, "T"]
        for parameter in data.parameter
    ]
    data["lower_change"] = 100 * (data.lower / data.baseline - 1)
    data["upper_change"] = 100 * (data.upper / data.baseline - 1)
    fig, ax = plt.subplots(figsize=(9.1, 4.9))
    fig.subplots_adjust(left=.34, right=.95, top=.73, bottom=.20)
    heading(fig, "When does the minimax choice switch?",
            "Each interval brackets a change in the recommendation between two tested input values.")
    labels = []
    for y, row in enumerate(data.itertuples()):
        city, place = row.venue.split("_")
        variable = "Upper SET threshold" if row.parameter == "cfg.set_upper" else "Hot-humid outdoor temperature"
        labels.append(f"{CITIES[city]} · {PLACES[place]}\n{variable}")
        ax.plot([row.lower_change, row.upper_change], [y, y], color="#B8C6D1", lw=4)
        for x, option in [(row.lower_change, row.choice_below), (row.upper_change, row.choice_above)]:
            ax.scatter(x, y, s=190, color=COLORS[option], zorder=3)
            ax.text(x, y, option, va="center", ha="center", color="white", weight="bold", zorder=4)
    ax.set_yticks(range(len(labels)), labels)
    ax.set(xlim=(-5.7, 5.7), ylim=(len(labels) - .5, -.5),
           xlabel="Change from the baseline input (%)", xticks=[-5, -2.5, 0, 2.5, 5])
    ax.axvline(0, color=MUTED, ls="--", lw=.9, zorder=0)
    ax.grid(axis="x", color="#E6EBF0")
    ax.set_axisbelow(True)
    ax.tick_params(length=0, pad=7)
    ax.spines["left"].set_visible(False)
    fig.text(.045, .038, "A · Fan     C · Larger evaporative     Inputs vary one at a time.", color=MUTED, size=9)
    save(fig, "F14_minimax_sensitivity_switches", data)


def dallas_transit_radar(radar):
    sites = {"DAL_BUS": "Dallas bus shelter", "DAL_RAIL": "Dallas rail platform"}
    data = radar.loc[radar.venue.isin(sites),
                     ["venue", "option", "axis", "metric", "raw", "scaled", "axis_maximum"]].copy()
    assert len(data) == 32 and np.allclose(data.scaled, data.raw / data.axis_maximum)
    angles = np.arange(4) * np.pi / 2
    closed = np.r_[angles, angles[0]]
    fig, panels = plt.subplots(1, 2, figsize=(10.5, 5.4), subplot_kw={"projection": "polar"})
    fig.subplots_adjust(left=.11, right=.89, top=.68, bottom=.26, wspace=.50)
    heading(fig, "Minimax radar for Dallas transit",
            "Worst-case regret and resource use across the three modeled weather scenarios.")
    for ax, (venue, title) in zip(panels, sites.items()):
        profiles = data[data.venue.eq(venue)].pivot(index="axis", columns="option", values="scaled")
        ax.set_theta_zero_location("N")
        ax.set_theta_direction(-1)
        ax.set_title(title, y=1.31, weight="bold")
        ax.set_xticks(angles, ["Maximum regret", "Purchase\nprice", "Electricity", "Evaporated\nwater"])
        ax.tick_params(axis="x", pad=15)
        ax.set(ylim=(0, 1), yticks=[.25, .5, .75, 1], yticklabels=["", "", "", ""])
        ax.grid(color="#C9D4DF", lw=.75)
        ax.spines["polar"].set_color("#A5B3C1")
        for option in OPTIONS:
            values = profiles[option].sort_index().to_numpy()
            ax.plot(closed, np.r_[values, values[0]], color=COLORS[option], marker="o", markersize=4,
                    linewidth=1.8, linestyle="--" if option == "NONE" else "-", label=OPTIONS[option])
    handles, labels = panels[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="lower center", bbox_to_anchor=(.5, .09), ncols=4, frameon=False)
    fig.text(.045, .035, "Both panels use the original D07 axis scales. The center is zero. "
             "The minimax choice uses maximum regret.", color=MUTED, size=9)
    save(fig, "F15_dallas_transit_minimax_radar", data)


if __name__ == "__main__":
    options = pd.read_csv("03_decision/result_options.csv")
    recommendations = pd.read_csv("03_decision/result_recommendations.csv")
    efficiency_figure(options)
    regret_figure(recommendations)
    radar = pd.read_csv("graphs/model_3/D07_minimax_decision_radar.csv")
    radar_figure(radar)
    dallas_transit_radar(radar)
    efficiency_case_map(options)
    energy_tradeoff(options)
    scaling_response(pd.read_csv("03_decision/result_venue_scaling.csv"))
    efficiency_head_to_head(options)
    regret_cost_tradeoff(recommendations, options)
    sensitivity_switches(pd.read_csv("04_sensitivity/result_sensitivity_switching.csv"),
                         pd.read_csv("weather_occ.csv"))
