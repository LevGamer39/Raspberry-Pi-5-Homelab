#!/usr/bin/env python3
import sys
import time
from lcd_monitor import lcd_driver

def main():
    lcd = lcd_driver()

    # если shutdown (poweroff/halt)
    if len(sys.argv) > 1 and sys.argv[1] == "poweroff":
        # Шаг 1: Shutting down...
        lcd.clear()
        lcd.display_string("Shutting down...", 2, clear=True)
        time.sleep(1)

        # Шаг 2: Offline
        lcd.display_string("Offline", 2, clear=True)
        time.sleep(1)

        # Выключаем подсветку
        lcd.backlight_off()

    # если reboot
    elif len(sys.argv) > 1 and sys.argv[1] == "reboot":
        lcd.clear()
        lcd.display_string("Rebooting...", 1, clear=True)
        time.sleep(1)
        # подсветка остаётся включённой

    # иначе — без действий
    else:
        pass

if __name__ == "__main__":
    main()

