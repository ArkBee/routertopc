# Гайд: Настройка туннелирования домашней сети через ПК с Windows с прошивкой роуйтера OPENWRT

**Цель:** Направить весь интернет-трафик от Wi-Fi устройств через компьютер с Windows, на котором запущен прокси-клиент (например, Nekobox) в режиме TUN.

Большинство домашних роутеров не могут обеспечить необходимую производительность для туннелирования всех домашних устроств.
Этот способ позволяет использовать вычислительную мощность ПК для шифрования трафика, что значительно быстрее, чем делать это на слабом процессоре роутера.

## Подготовка

*   **На ПК:**
    *   Установите прокси-клиент с поддержкой TUN-режима (например, [Nekobox](https://github.com/MatsuriDayo/nekoray)).
    *   Убедитесь, что клиент настроен и работает в TUN-режиме.
    *   Подключите ПК к роутеру по сетевому кабелю (Ethernet) для максимальной стабильности.

*   **На роутере:**
    *   Убедитесь, что у вас установлен OpenWrt.
    *   Подключитесь к роутеру по SSH.

---

## Шаг 1: Настройка ПК (Windows)

### 1. Статический IP-адрес
Назначьте вашему ПК постоянный IP-адрес в настройках роутера через DHCP-резервацию (привязка по MAC-адресу). Например, `192.168.1.100`.

### 2. Включение TUN-режима
Запустите ваш прокси-клиент (Nekobox) и активируйте TUN-режим. Убедитесь, что интернет на самом ПК теперь идет через прокси (проверьте свой IP на сайте `2ip.ru`).

### 3. Настройка шлюза
Превращаем ПК в шлюз для других устройств. Используйте один из двух способов.

*   **Способ А (простой): "Общий доступ к Интернету" (ICS)**
    1.  Найдите в сетевых подключениях **виртуальный адаптер** от вашего прокси-клиента.
    2.  Откройте его "Свойства" -> вкладка "Доступ".
    3.  Поставьте галочку "Разрешить другим пользователям сети использовать подключение...".
    4.  В выпадающем списке выберите ваш **физический `Ethernet` адаптер**.
    5.  Нажмите "ОК". Windows автоматически назначит вашему `Ethernet` адаптеру IP-адрес `192.168.137.1`.

*   **Способ Б (если ICS не работает из-за Hyper-V/WSL): PowerShell**
    1.  Откройте PowerShell от имени администратора.
    2.  Выполните команду:
        ```powershell
        New-NetNAT -Name "NekoNAT" -InternalIPInterfaceAddressPrefix "192.168.137.0/24"
        ```

### 4. Настройка Брандмауэра
Если после настройки у клиентских устройств не будет работать интернет, разрешите входящие DNS-запросы в брандмауэре Windows.

Откройте PowerShell от имени администратора и выполните:
```powershell
New-NetFirewallRule -DisplayName "Allow Inbound DNS (UDP)" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 53
New-NetFirewallRule -DisplayName "Allow Inbound DNS (TCP)" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 53
```

---

## Шаг 2: Настройка роутера (OpenWrt)

Создадим удобный переключатель для включения и выключения режима туннелирования.

### 1. Создание скрипта-переключателя
Создайте на роутере файл `/root/tunnel_mode.sh` со следующим содержимым:

```bash
#!/bin/sh

# --- NASTROYKI ---
# IP-adres shlyuza na vashem PK (obychno 192.168.137.1 posle vklyucheniya ICS)
PC_GATEWAY_IP="192.168.137.1"

# IP-adres samogo routera (standartnyy shlyuz)
ROUTER_IP="192.168.1.1"

# Publichnye DNS-servery dlya rezhima tunnelirovaniya
PUBLIC_DNS_1="1.1.1.1"
PUBLIC_DNS_2="8.8.8.8" # Rezervnyy
# --- KONETS NASTROEK ---

# Funktsiya dlya vklyucheniya rezhima tunnelirovaniya
start_tunnel() {
    echo "Vklyuchaem rezhim tunnelirovaniya cherez PK ($PC_GATEWAY_IP)..."
    uci -q delete dhcp.lan.dhcp_option
    uci add_list dhcp.lan.dhcp_option="3,$PC_GATEWAY_IP"
    uci add_list dhcp.lan.dhcp_option="6,$PUBLIC_DNS_1"
    uci add_list dhcp.lan.dhcp_option="6,$PUBLIC_DNS_2"
    uci commit dhcp
    /etc/init.d/dnsmasq restart
    echo "Rezhim tunnelirovaniya vklyuchen. Perezagruzite Wi-Fi na vashih ustroystvah."
}

# Funktsiya dlya vyklyucheniya rezhima tunnelirovaniya
stop_tunnel() {
    echo "Vyklyuchaem rezhim tunnelirovaniya. Vozvrashchaem standartnyy marshrut..."
    uci -q delete dhcp.lan.dhcp_option
    uci add_list dhcp.lan.dhcp_option="3,$ROUTER_IP"
    uci add_list dhcp.lan.dhcp_option="6,$ROUTER_IP"
    uci commit dhcp
    /etc/init.d/dnsmasq restart
    echo "Rezhim tunnelirovaniya vyklyuchen. Perezagruzite Wi-Fi na vashih ustroystvah."
}

case "$1" in
    start) start_tunnel ;;
    stop) stop_tunnel ;;
    *) echo "Ispol'zovanie: $0 {start|stop}"; exit 1 ;;
esac

exit 0
```

### 2. Предоставление прав на выполнение
Сделайте скрипт исполняемым:
```bash
chmod +x /root/tunnel_mode.sh
```

### 3. (Опционально) Создание удобных команд
Отредактируйте файл `/etc/profile` и добавьте в конец эти строки для создания коротких команд:
```bash
alias tunnel-on='/root/tunnel_mode.sh start'
alias tunnel-off='/root/tunnel_mode.sh stop'
```
Примените изменения, выполнив `source /etc/profile`.

---

## Шаг 3: Использование

1.  **Включить туннель:** На роутере выполните команду `tunnel-on`.
2.  **Переподключить устройство:** На телефоне, ноутбуке или другом устройстве выключите и снова включите Wi-Fi, чтобы оно получило новые настройки.
3.  **Проверить:** Зайдите на `ip-api.com` — должен отображаться IP-адрес вашего прокси.
4.  **Выключить туннель:** На роутере выполните команду `tunnel-off` и снова переподключите Wi-Fi на устройстве, чтобы вернуться к обычному режиму.
