import glob
import re

files = glob.glob('lib/widgets/charts/*.dart')

for f in files:
    with open(f, 'r') as file:
        content = file.read()
    
    # 1. ensure appSettingsProvider is imported
    if 'appSettingsProvider' not in content:
        # insert import
        content = content.replace("import 'chart_helpers.dart';", "import 'chart_helpers.dart';\nimport '../../providers/app_settings_provider.dart';")
    
    # 2. Add `final currency = ref.watch(appSettingsProvider).currency;`
    # We find `Widget build(BuildContext context, WidgetRef ref) {`
    # and insert it.
    if 'final currency = ref.watch(appSettingsProvider).currency;' not in content:
        content = content.replace(
            "Widget build(BuildContext context, WidgetRef ref) {", 
            "Widget build(BuildContext context, WidgetRef ref) {\n    final currency = ref.watch(appSettingsProvider).currency;"
        )
        content = content.replace(
            "Widget build(BuildContext context) {",
            "Widget build(BuildContext context) {\n    // Note: requires ConsumerWidget for currency"
        )
    
    # 3. Replace currencyFmt with getCurrencyFmt(currency)
    content = content.replace("currencyFmt.", "getCurrencyFmt(currency).")
    content = content.replace("currencyFmtDec.", "getCurrencyFmtDec(currency).")
    
    # 4. Replace shortCurrency(value) with shortCurrency(value, currency)
    content = content.replace("shortCurrency(value)", "shortCurrency(value, currency)")
    
    with open(f, 'w') as file:
        file.write(content)

