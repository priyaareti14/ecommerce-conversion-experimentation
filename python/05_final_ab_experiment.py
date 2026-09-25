import numpy as np
import pandas as pd
from scipy.stats import norm
from statsmodels.stats.proportion import proportions_ztest

SEED = 42
N_PER_GROUP = 4229
CONTROL_PAYMENT_RATE = 0.5715
TREATMENT_PAYMENT_RATE = 0.6015
PAYMENT_TO_PURCHASE_RATE = 0.7054
GUARDRAIL_MARGIN = -0.02
ALPHA = 0.05

rng = np.random.default_rng(SEED)

groups = np.array(["Control"]*N_PER_GROUP + ["Treatment"]*N_PER_GROUP)
payment_probs = np.array(
    [CONTROL_PAYMENT_RATE]*N_PER_GROUP +
    [TREATMENT_PAYMENT_RATE]*N_PER_GROUP
)

payment = rng.binomial(1, payment_probs)
purchase = np.zeros(len(groups), dtype=int)
mask = payment == 1
purchase[mask] = rng.binomial(1, PAYMENT_TO_PURCHASE_RATE, mask.sum())

df = pd.DataFrame({
    "group": groups,
    "payment_conversion": payment,
    "purchase_conversion": purchase
})

summary = df.groupby("group").agg(
    users=("payment_conversion","size"),
    payment_users=("payment_conversion","sum"),
    purchase_users=("purchase_conversion","sum")
)
summary["payment_rate"] = summary.payment_users / summary.users
summary["purchase_given_payment"] = summary.purchase_users / summary.payment_users

c = summary.loc["Control"]
t = summary.loc["Treatment"]

lift = t.payment_rate - c.payment_rate
rel_lift = lift / c.payment_rate

z_stat, p_value = proportions_ztest(
    [t.payment_users, c.payment_users],
    [t.users, c.users],
    alternative="two-sided"
)

zcrit = norm.ppf(0.975)
se = np.sqrt(
    t.payment_rate*(1-t.payment_rate)/t.users +
    c.payment_rate*(1-c.payment_rate)/c.users
)
ci_low, ci_high = lift-zcrit*se, lift+zcrit*se

gdiff = t.purchase_given_payment - c.purchase_given_payment
gse = np.sqrt(
    t.purchase_given_payment*(1-t.purchase_given_payment)/t.payment_users +
    c.purchase_given_payment*(1-c.purchase_given_payment)/c.payment_users
)
g_low, g_high = gdiff-zcrit*gse, gdiff+zcrit*gse

primary_pass = (p_value < ALPHA) and (ci_low > 0)
guardrail_pass = g_low > GUARDRAIL_MARGIN

print("FINAL SIMULATED A/B EXPERIMENT")
print("="*60)
print(f"Control: {c.payment_users:,}/{c.users:,} = {c.payment_rate:.2%}")
print(f"Treatment: {t.payment_users:,}/{t.users:,} = {t.payment_rate:.2%}")
print(f"Absolute lift: {lift*100:.2f} pp")
print(f"Relative lift: {rel_lift:.2%}")
print(f"95% CI: {ci_low*100:.2f} to {ci_high*100:.2f} pp")
print(f"P-value: {p_value:.4f}")
print(f"Guardrail difference: {gdiff*100:.2f} pp")
print(f"Guardrail 95% CI: {g_low*100:.2f} to {g_high*100:.2f} pp")
print("Decision:", "PASS" if primary_pass and guardrail_pass else "DO NOT ROLL OUT")
