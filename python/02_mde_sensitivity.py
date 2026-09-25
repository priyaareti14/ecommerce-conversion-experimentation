from statsmodels.stats.power import NormalIndPower
from statsmodels.stats.proportion import proportion_effectsize
import math

baseline_rate = 0.5715
alpha = 0.05
power = 0.80
mde_values = [0.01, 0.02, 0.03, 0.04, 0.05]
analysis = NormalIndPower()

print("MDE SENSITIVITY ANALYSIS")
print("-" * 70)

for mde in mde_values:
    target_rate = baseline_rate + mde
    effect_size = abs(proportion_effectsize(baseline_rate, target_rate))
    sample_size = analysis.solve_power(
        effect_size=effect_size,
        power=power,
        alpha=alpha,
        ratio=1,
        alternative="two-sided"
    )
    n = math.ceil(sample_size)
    print(
        f"MDE: {mde*100:.0f} pp | Target: {target_rate:.2%} | "
        f"Per group: {n:,} | Total: {2*n:,}"
    )
