#!/usr/bin/env python3
###########################################
#
# Usage: python centiloid_calibration.py Tracer calibration_tracer.csv
#
###########################################

import pandas as pd
import statsmodels.api as sm
import matplotlib.pyplot as plt
import sys
import os

def fit_calibration(csv_path, tracer_name):
    # Load data
    df = pd.read_csv(csv_path)
    if not {'mSUVr','PiB_SUVR'}.issubset(df.columns):
        raise ValueError("CSV must contain columns: mSUVr, PiB_SUVR")

    # Fit regression
    X = sm.add_constant(df['mSUVr'])
    model = sm.OLS(df['PiB_SUVR'], X).fit()
    m, b = model.params[1], model.params[0]

    print(f"=== {tracer_name} ===")
    print(f"Slope (m):     {m:.4f}")
    print(f"Intercept (b): {b:.4f}")
    print(f"R²:            {model.rsquared:.4f}")
    print(model.summary())

    # Plot regression
    plt.figure(figsize=(5,5))
    plt.scatter(df['mSUVr'], df['PiB_SUVR'], color='blue', label='Subjects')
    plt.plot(df['mSUVr'], m*df['mSUVr'] + b, color='red', label=f'Fit: y={m:.3f}x+{b:.3f}')
    plt.xlabel('mSUVr (Your tracer)')
    plt.ylabel('PiB SUVR (standard method)')
    plt.title(f'Calibration for {tracer_name}')
    plt.legend()
    plt.grid(True)
    plt.tight_layout()
    plt.savefig(f'{tracer_name}_calibration_plot.png', dpi=150)
    plt.close()

    # Save coefficients
    out = {
        "tracer": tracer_name,
        "slope_m": m,
        "intercept_b": b,
        "r_squared": model.rsquared
    }
    coef_path = f'{tracer_name}_coefficients.csv'
    pd.DataFrame([out]).to_csv(coef_path, index=False)
    print(f"Saved coefficients to {coef_path}\n")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python centiloid_calibration.py <tracer_name> <calibration_csv>")
        sys.exit(1)
    tracer_name, csv_path = sys.argv[1], sys.argv[2]
    fit_calibration(csv_path, tracer_name)
