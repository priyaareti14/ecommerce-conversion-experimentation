from statsmodels.stats.power import NormalIndPower
from statsmodels.stats.proportion import proportion_effectsize
import math

baseline_rate = 0.5715
target_rate = 0.6015
alpha = 0.05
power = 0.80

effect_size = proportion_effectsize(baseline_rate, target_rate)
analysis = NormalIndPower()

sample_size = analysis.solve_power(
    effect_size=abs(effect_size),
    power=power,
    alpha=alpha,
    ratio=1,
    alternative="two-sided"
)

n_per_group = math.ceil(sample_size)
print(f"Baseline conversion: {baseline_rate:.2%}")
print(f"Target conversion: {target_rate:.2%}")
print(f"MDE: {(target_rate-baseline_rate)*100:.1f} percentage points")
print(f"Required sample per group: {n_per_group:,}")
print(f"Total required sample: {2*n_per_group:,}")
