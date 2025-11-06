import sys
import smbus
import psutil
from time import sleep
import logging
from datetime import datetime

# Настройка логирования
#logging.basicConfig(filename="monitor.log", level=logging.ERROR)

# Класс I2C-устройства
class i2c_device:
    def __init__(self, addr, port=1):
        self.addr = addr
        try:
            self.bus = smbus.SMBus(port)
        except Exception as e:
            logging.error(f"I2C init error: {e}")
            sys.exit(1)

    def write_cmd(self, cmd):
        try:
            self.bus.write_byte(self.addr, cmd)
            sleep(0.0001)
        except Exception as e:
            logging.error(f"I2C cmd write error: {e}")

    def write_cmd_arg(self, cmd, data):
        try:
            self.bus.write_byte_data(self.addr, cmd, data)
            sleep(0.0001)
        except Exception as e:
            logging.error(f"I2C cmd+arg write error: {e}")

    def write_block_data(self, cmd, data):
        try:
            self.bus.write_block_data(self.addr, cmd, data)
            sleep(0.0001)
        except Exception as e:
            logging.error(f"I2C block write error: {e}")

# Константы LCD
ADDRESS = 0x27
LCD_CLEARDISPLAY = 0x01
LCD_RETURNHOME = 0x02
LCD_ENTRYMODESET = 0x04
LCD_DISPLAYCONTROL = 0x08
LCD_CURSORSHIFT = 0x10
LCD_FUNCTIONSET = 0x20
LCD_SETCGRAMADDR = 0x40
LCD_SETDDRAMADDR = 0x80
LCD_ENTRYLEFT = 0x02
LCD_DISPLAYON = 0x04
LCD_2LINE = 0x08
LCD_5x8DOTS = 0x00
LCD_4BITMODE = 0x00
LCD_BACKLIGHT = 0x08
En = 0b00000100
Rs = 0b00000001

# Драйвер LCD
class lcd_driver:
    def __init__(self):
        self.device = i2c_device(ADDRESS)
        self.backlight_enabled = False  # начальное состояние — подсветка выключена

        try:
            self.write(0x03)
            self.write(0x03)
            self.write(0x03)
            self.write(0x02)
            self.write(LCD_FUNCTIONSET | LCD_2LINE | LCD_5x8DOTS | LCD_4BITMODE)
            self.write(LCD_DISPLAYCONTROL | LCD_DISPLAYON)
            self.write(LCD_CLEARDISPLAY)
            self.write(LCD_ENTRYMODESET | LCD_ENTRYLEFT)
            sleep(0.2)
        except Exception as e:
            logging.error(f"LCD init error: {e}")
            sys.exit(1)

    def strobe(self, data):
        try:
            cmd = data | En
            if self.backlight_enabled:
                cmd |= LCD_BACKLIGHT
            self.device.write_cmd(cmd)
            sleep(0.0005)
            cmd = (data & ~En)
            if self.backlight_enabled:
                cmd |= LCD_BACKLIGHT
            self.device.write_cmd(cmd)
            sleep(0.0001)
        except Exception as e:
            logging.error(f"LCD strobe error: {e}")

    def write_four_bits(self, data):
        try:
            cmd = data
            if self.backlight_enabled:
                cmd |= LCD_BACKLIGHT
            self.device.write_cmd(cmd)
            self.strobe(data)
        except Exception as e:
            logging.error(f"LCD 4-bit write error: {e}")

    def write(self, cmd, mode=0):
        try:
            self.write_four_bits(mode | (cmd & 0xF0))
            self.write_four_bits(mode | ((cmd << 4) & 0xF0))
        except Exception as e:
            logging.error(f"LCD cmd write error: {e}")

    def display_string(self, string, line, clear=False):
        try:
            if clear:
                self.write(LCD_CLEARDISPLAY)
                sleep(0.002)
            if line == 1:
                self.write(0x80)
            elif line == 2:
                self.write(0xC0)
            elif line == 3:
                self.write(0x94)
            elif line == 4:
                self.write(0xD4)
            for char in string.ljust(20)[:20]:
                self.write(ord(char), Rs)
        except Exception as e:
            logging.error(f"LCD display error: {e}")

    def clear(self):
        try:
            self.write(LCD_CLEARDISPLAY)
            self.write(LCD_RETURNHOME)
        except Exception as e:
            logging.error(f"LCD clear error: {e}")

    def backlight_on(self):
        try:
            self.backlight_enabled = True
            self.device.write_cmd(LCD_BACKLIGHT)
        except Exception as e:
            logging.error(f"Backlight ON error: {e}")

    def backlight_off(self):
        try:
            self.backlight_enabled = False
            self.device.write_cmd(0x00)
        except Exception as e:
            logging.error(f"Backlight OFF error: {e}")

# Чтение температуры CPU
def get_cpu_temperature():
    try:
        with open("/sys/class/thermal/thermal_zone0/temp") as f:
            temp = int(f.read()) / 1000.0
            return round(temp, 1)
    except Exception as e:
        logging.error(f"CPU temp read error: {e}")
        return 0.0

# Главная функция
def main():
    lcd = lcd_driver()

    now = datetime.now().time()
    if now.hour >= 22 or now.hour < 10:
        lcd.backlight_off()
        backlight_is_on = False
    else:
        lcd.backlight_on()
        backlight_is_on = True

    prev_line_one, prev_line_two = "", ""

    try:
        while True:
            cpu_usage = psutil.cpu_percent()
            cpu_temp = get_cpu_temperature()
            mem = psutil.virtual_memory()
            mem_used_gb = mem.used / (1024 ** 3)
            mem_total_gb = mem.total / (1024 ** 3)

            line_one = f"CPU:{cpu_usage:>3.1f}% T:{cpu_temp:>3.1f}C"[:20]
            line_two = f"MEM:{mem_used_gb:>3.2f}/{mem_total_gb:>3.2f}GB"[:20]

            if line_one != prev_line_one or line_two != prev_line_two:
                lcd.display_string(line_one, 1, clear=True)
                lcd.display_string(line_two, 2)
                prev_line_one, prev_line_two = line_one, line_two

            # Управление подсветкой по времени (только при смене)
            now = datetime.now().time()
            if (now.hour >= 22 or now.hour < 10):
                if backlight_is_on:
                    lcd.backlight_off()
                    backlight_is_on = False
            else:
                if not backlight_is_on:
                    lcd.backlight_on()
                    backlight_is_on = True

            sleep(2)

    except KeyboardInterrupt:
        lcd.clear()
        lcd.backlight_off()
        sys.exit(0)

if __name__ == "__main__":
    main()
