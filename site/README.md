# Public site templates

При установке TgWebProxyR случайно выбирает один из шаблонов в `templates/`
и копирует его в `/srv/tproxy-site` (placeholder `__HOSTNAME__` → ваш домен).

| id | Название |
| --- | --- |
| northwind | Northwind Field Notes (гавань) |
| atelier | Atelier Lane Studio (мастерская) |
| alpine | Ridge Line Almanac (тропы) |
| metro | Gridline Dispatch (транспорт) |
| orchard | Greenrow Press (сад) |
| signal | Beacon Range Club (радио) |
| library | Cedar Branch Library |
| kiln | Clayroom Bulletin (керамика) |
| reef | Tidepool Observer |
| foundry | Typecase Works (типография) |

```bash
# при установке (по умолчанию random)
TWPR_SITE_TEMPLATE=metro sudo bash install.sh …

# позже
sudo tgwebproxyr site list
sudo tgwebproxyr site set alpine
sudo tgwebproxyr site random
```

Перегенерация шаблонов из репо: `python3 scripts/gen-site-templates.py`
