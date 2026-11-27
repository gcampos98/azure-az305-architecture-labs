#!/usr/bin/env python3
"""Genera la directiva de Azure Backup con retención a largo plazo (LTR) para VMs.

Uso: ltr_policy.py <diaria_días> <semanal_semanas> <mensual_meses> <anual_años>
Imprime el JSON que recibe `az backup policy create --policy`.
"""
import json
import sys

# Hora del respaldo diario (UTC). La fecha es solo un marcador exigido por el formato.
TIME = "2026-01-01T03:00:00Z"
FIRST_SUNDAY = {"daysOfTheWeek": ["Sunday"], "weeksOfTheMonth": ["First"]}


def duration(count, unit):
    return {"count": count, "durationType": unit}


def policy(daily, weekly, monthly, yearly):
    return {
        "properties": {
            "backupManagementType": "AzureIaasVM",
            "instantRpRetentionRangeInDays": 2,
            "timeZone": "UTC",
            "schedulePolicy": {
                "schedulePolicyType": "SimpleSchedulePolicy",
                "scheduleRunFrequency": "Daily",
                "scheduleRunTimes": [TIME],
            },
            "retentionPolicy": {
                "retentionPolicyType": "LongTermRetentionPolicy",
                "dailySchedule": {
                    "retentionTimes": [TIME],
                    "retentionDuration": duration(daily, "Days"),
                },
                "weeklySchedule": {
                    "daysOfTheWeek": ["Sunday"],
                    "retentionTimes": [TIME],
                    "retentionDuration": duration(weekly, "Weeks"),
                },
                "monthlySchedule": {
                    "retentionScheduleFormatType": "Weekly",
                    "retentionScheduleWeekly": FIRST_SUNDAY,
                    "retentionTimes": [TIME],
                    "retentionDuration": duration(monthly, "Months"),
                },
                "yearlySchedule": {
                    "retentionScheduleFormatType": "Weekly",
                    "monthsOfYear": ["January"],
                    "retentionScheduleWeekly": FIRST_SUNDAY,
                    "retentionTimes": [TIME],
                    "retentionDuration": duration(yearly, "Years"),
                },
            },
        }
    }


if __name__ == "__main__":
    if len(sys.argv) != 5 or not all(a.isdigit() for a in sys.argv[1:]):
        sys.exit(__doc__)
    values = [int(a) for a in sys.argv[1:]]
    if values[0] < 7:
        sys.exit("La retención diaria mínima es de 7 días.")
    print(json.dumps(policy(*values), indent=2))
