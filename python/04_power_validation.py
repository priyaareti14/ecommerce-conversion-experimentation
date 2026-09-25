import numpy as np
from scipy.stats import norm

baseline_rate = 0.5715
treatment_rate = 0.6015
n_control = n_treatment = 4229
alpha = 0.05
n_simulations = 10000
rng = np.random.default_rng(42)

def pvals(c, t):
    pc = c / n_control
    pt = t / n_treatment
    pooled = (c+t) / (n_control+n_treatment)
    se = np.sqrt(pooled*(1-pooled)*(1/n_control+1/n_treatment))
    z = (pt-pc)/se
    return 2*(1-norm.cdf(np.abs(z)))

c = rng.binomial(n_control, baseline_rate, n_simulations)
t = rng.binomial(n_treatment, treatment_rate, n_simulations)
empirical_power = np.mean(pvals(c, t) < alpha)

c0 = rng.binomial(n_control, baseline_rate, n_simulations)
t0 = rng.binomial(n_treatment, baseline_rate, n_simulations)
type1 = np.mean(pvals(c0, t0) < alpha)

print("EXPERIMENT DESIGN VALIDATION")
print(f"Empirical power: {empirical_power:.2%}")
print(f"Empirical false-positive rate: {type1:.2%}")
