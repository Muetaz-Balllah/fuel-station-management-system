class RoleCode:
    STATION_MANAGER = "station_manager"
    OPERATOR = "operator"

    ALL = (STATION_MANAGER, OPERATOR)


ROLE_NAMES = {
    RoleCode.STATION_MANAGER: "مدير المحطة",
    RoleCode.OPERATOR: "عامل المضخة",
}


class PermissionCode:
    DASHBOARD_VIEW = "dashboard.view"
    ASSETS_MANAGE = "assets.manage"
    SUPPLY_MANAGE = "supply.manage"
    SUPPLY_RECEIVE = "supply.receive"
    ATTENDANCE_MANAGE = "attendance.manage"
    SHIFTS_OPERATE = "shifts.operate"
    SHIFTS_APPROVE = "shifts.approve"
    SHIFTS_VIEW_ALL = "shifts.view_all"
    PRICES_MANAGE = "prices.manage"
    SETTINGS_MANAGE = "settings.manage"
    USERS_MANAGE = "users.manage"
    REPORTS_EXPORT = "reports.export"
    METER_OVERRIDE = "meter.override"
    INVENTORY_ADJUST = "inventory.adjust"

    ALL = [
        DASHBOARD_VIEW,
        ASSETS_MANAGE,
        SUPPLY_MANAGE,
        SUPPLY_RECEIVE,
        ATTENDANCE_MANAGE,
        SHIFTS_OPERATE,
        SHIFTS_APPROVE,
        SHIFTS_VIEW_ALL,
        PRICES_MANAGE,
        SETTINGS_MANAGE,
        USERS_MANAGE,
        REPORTS_EXPORT,
        METER_OVERRIDE,
        INVENTORY_ADJUST,
    ]


def permissions_for(role: str) -> list[str]:
    if role == RoleCode.STATION_MANAGER:
        return list(PermissionCode.ALL)
    if role == RoleCode.OPERATOR:
        return [PermissionCode.SHIFTS_OPERATE]
    return []