import numpy as np
from scipy.stats import chisquare
from statsmodels.stats.proportion import proportions_ztest

n_a, n_b = 4772, 4780
conv_a, conv_b = 2756, 2703

observed = np.array([n_a, n_b])
expected = np.array([(n_a+n_b)/2, (n_a+n_b)/2])
chi2_stat, srm_p = chisquare(observed, f_exp=expected)

z_stat, aa_p = proportions_ztest(
    np.array([conv_a, conv_b]),
    np.array([n_a, n_b]),
    alternative="two-sided"
)

rate_a, rate_b = conv_a/n_a, conv_b/n_b

print("A/A VALIDATION")
print("-" * 50)
print(f"Group A users: {n_a:,}")
print(f"Group B users: {n_b:,}")
print(f"SRM p-value: {srm_p:.4f}")
print(f"Group A conversion: {rate_a:.2%}")
print(f"Group B conversion: {rate_b:.2%}")
print(f"Absolute difference: {(rate_a-rate_b)*100:.2f} percentage points")
print(f"A/A p-value: {aa_p:.4f}")
