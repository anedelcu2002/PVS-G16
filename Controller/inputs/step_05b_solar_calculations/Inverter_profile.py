import math
from pathlib import Path

import numpy as np
import pandas as pd
import pvlib

# =========================================================
# INPUT / OUTPUT
# =========================================================
BASE_DIR = Path(__file__).resolve().parent
INPUT_CSV = BASE_DIR / "Weather_Data_KNMI.csv"

# Output: ONE inverter block only
OUTPUT_CSV = BASE_DIR / "Solar_1_Inverter_Profile_2024_hourly.csv"

# =========================================================
# LOCATION + ARRAY ORIENTATION
# =========================================================
LATITUDE = 52.1561   # Amersfoort
LONGITUDE = 5.3878
TILT_DEG = 37.0
AZIMUTH_DEG = 180.0  # south-facing

# =========================================================
# PV MODULE (Trina Vertex N 620 W)
# =========================================================
G_STC_W_M2 = 1000.0
T_STC_C = 25.0
P_STC_W = 620.0
VOC_STC_V = 49.6
ISC_STC_A = 15.91
VMP_STC_V = 41.4
IMP_STC_A = 14.99

N_CELLS_SERIES = 132
KP_PERCENT_PER_C = -0.29     # %/°C
BETA_VOC_PER_C = -0.0024     # 1/°C

K_B = 1.380649e-23
Q_E = 1.602176634e-19
V_T_STC = K_B * (T_STC_C + 273.15) / Q_E

FF_STC = P_STC_W / (VOC_STC_V * ISC_STC_A)

# =========================================================
# FAIMAN MODULE TEMPERATURE MODEL
# =========================================================
U0 = 25.0
U1 = 6.8

# =========================================================
# INVERTER (Huawei SUN2000-330KTL-H1)
# =========================================================
INV = {
    "Vdc_max_V": 1500.0,
    "Vmppt_min_V": 500.0,
    "Vdc_nom_V": 1080.0,
    "I_mppt_max_A": 65.0,
    "Isc_mppt_max_A": 115.0,
    "mppt_inputs": [4, 5, 5, 4, 5, 5],  # max PV inputs per MPPT
    "P_ac_max_W": 330_000.0,
    "eta_inv": 0.988,
}

# =========================================================
# HELPERS
# =========================================================
def read_weather_csv(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path)

    df["DateTime"] = pd.to_datetime(df["DateTime"], dayfirst=True)
    df["T (C)"] = pd.to_numeric(df["T (C)"], errors="coerce")
    df["G (W/m2)"] = pd.to_numeric(df["G (W/m2)"], errors="coerce").clip(lower=0)
    df["v (m/s)"] = pd.to_numeric(df["v (m/s)"], errors="coerce").clip(lower=0)

    df = df.dropna(subset=["DateTime", "T (C)", "G (W/m2)", "v (m/s)"])

    # Keep 2024 and localize to UTC
    df["DateTime_UTC"] = df["DateTime"].dt.tz_localize("UTC")
    df = df.set_index("DateTime_UTC").sort_index()

    return df.loc["2024"].copy()


def choose_topology_simple(df: pd.DataFrame):
    """
    Topology sizing:
    - N_s from inverter voltage compatibility
    - N_p from MPPT current limits + physical MPPT inputs
    """
    # Cold-condition Voc for max string length
    T_cold = float(df["T (C)"].min())
    Voc_cold = VOC_STC_V * (1 + BETA_VOC_PER_C * (T_cold - T_STC_C))

    Ns_max = math.floor(INV["Vdc_max_V"] / Voc_cold)
    Ns_min = math.ceil(INV["Vmppt_min_V"] / VMP_STC_V)
    Ns_nom = round(INV["Vdc_nom_V"] / VMP_STC_V)

    N_s = max(Ns_min, min(Ns_nom, Ns_max))

    # Parallel strings limited by MPPT current + MPPT physical inputs
    n_by_imp = math.floor(INV["I_mppt_max_A"] / IMP_STC_A)
    n_by_isc = math.floor(INV["Isc_mppt_max_A"] / ISC_STC_A)
    mppt_caps = [min(n_in, n_by_imp, n_by_isc) for n_in in INV["mppt_inputs"]]

    N_p = sum(mppt_caps)
    return N_s, N_p, mppt_caps


# =========================================================
# MAIN
# =========================================================
def main():
    df = read_weather_csv(INPUT_CSV)

    # KNMI hourly timestamps are often end-of-interval -> use midpoint
    t_mid = df.index - pd.Timedelta(minutes=30)

    # 1) Solar position
    solpos = pvlib.solarposition.get_solarposition(t_mid, LATITUDE, LONGITUDE)

    # 2) GHI -> DNI + DHI using Erbs
    ghi = df["G (W/m2)"].to_numpy()
    zen = solpos["zenith"].to_numpy()

    erbs = pvlib.irradiance.erbs(ghi=ghi, zenith=zen, datetime_or_doy=t_mid)
    dni = np.clip(np.nan_to_num(erbs["dni"]), 0, None)
    dhi = np.clip(np.nan_to_num(erbs["dhi"]), 0, None)

    # 3) GHI -> POA irradiance
    dni_extra = pvlib.irradiance.get_extra_radiation(t_mid)
    poa = pvlib.irradiance.get_total_irradiance(
        surface_tilt=TILT_DEG,
        surface_azimuth=AZIMUTH_DEG,
        solar_zenith=solpos["apparent_zenith"].to_numpy(),
        solar_azimuth=solpos["azimuth"].to_numpy(),
        dni=dni,
        ghi=ghi,
        dhi=dhi,
        dni_extra=dni_extra,
        model="haydavies",
        albedo=0.20,
    )
    df["G_POA_W_m2"] = np.clip(np.nan_to_num(poa["poa_global"]), 0, None)

    # 4) Faiman module temperature
    df["T_module_C"] = df["T (C)"] + df["G_POA_W_m2"] / (U0 + U1 * df["v (m/s)"])

    # 5) Module power model
    Gm = df["G_POA_W_m2"]
    Tm = df["T_module_C"]
    mask = Gm > 0

    # Isc(G)
    df["I_sc_A"] = 0.0
    df.loc[mask, "I_sc_A"] = ISC_STC_A * (Gm[mask] / G_STC_W_M2)

    # Voc(G)
    df["V_oc_V"] = 0.0
    df.loc[mask, "V_oc_V"] = (
        VOC_STC_V
        + N_CELLS_SERIES * V_T_STC * np.log(Gm[mask] / G_STC_W_M2)
    )

    # Irradiance-only module power
    df["P_dc_G_W"] = 0.0
    df.loc[mask, "P_dc_G_W"] = (
        FF_STC * df.loc[mask, "I_sc_A"] * df.loc[mask, "V_oc_V"]
    )

    # Temperature correction
    temp_factor = 1 + (KP_PERCENT_PER_C / 100.0) * (Tm - T_STC_C)
    df["P_mod_DC_W"] = np.maximum(0.0, df["P_dc_G_W"] * temp_factor)

    # 6) Topology sizing (ONE inverter block)
    N_s, N_p, mppt_caps = choose_topology_simple(df)
    modules_per_inverter = N_s * N_p

    # 7) Include inverter efficiency + clipping
    df["P_inv_DC_W"] = modules_per_inverter * df["P_mod_DC_W"]
    df["P_inv_AC_W"] = np.minimum(
        df["P_inv_DC_W"] * INV["eta_inv"],
        INV["P_ac_max_W"]
    )

    # 8) Optional hourly energy for one inverter block
    df["E_inv_AC_J"] = df["P_inv_AC_W"] * 3600.0

    # 9) Output CSV for ONE inverter only
    out = pd.DataFrame({
        "DateTime": df.index.tz_convert(None).strftime("%d-%b-%Y %H:%M:%S"),
        "E_inv_AC_J": df["E_inv_AC_J"].values,
        "P_inv_AC_W": df["P_inv_AC_W"].values,
        "G_POA_W_m2": df["G_POA_W_m2"].values,
        "T_module_C": df["T_module_C"].values,
        "P_inv_DC_W": df["P_inv_DC_W"].values,
    })
    out.to_csv(OUTPUT_CSV, index=False)

    # 10) Summary
    E_one_inv_kWh = float(df["P_inv_AC_W"].sum() / 1000.0)
    total_modules = modules_per_inverter

    print("=== 1-inverter solar profile created ===")
    print(f"Output file                  : {OUTPUT_CSV}")
    print(f"N_s (modules/string)         : {N_s}")
    print(f"N_p (strings/inverter)       : {N_p}")
    print(f"MPPT string caps             : {mppt_caps}")
    print(f"Modules per inverter         : {modules_per_inverter}")
    print(f"Total solar modules          : {total_modules}")
    print(f"Annual energy of 1 inverter  : {E_one_inv_kWh:.2f} kWh/year")
    print(f"Peak AC output               : {df['P_inv_AC_W'].max()/1000:.2f} kW")
    print(f"Mean AC output               : {df['P_inv_AC_W'].mean()/1000:.2f} kW")


if __name__ == "__main__":
    main()