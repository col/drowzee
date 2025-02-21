# SleepSchedule CRD Conditions

The `SleepSchedule` Custom Resource Definition (CRD) manages the sleeping and waking of Kubernetes deployments based on a defined schedule or manual triggers. To track the current state of the system and operations, the CRD uses a set of standardized conditions stored in its `status` field.

This document describes the conditions used and how they reflect the state of the system.

---

## Conditions Overview

The `SleepSchedule` CRD uses four conditions:

| **Condition**          | **Description**                                    | **Possible Values** | **Reason Examples**           |
|------------------------|-----------------------------------------------------|---------------------|--------------------------------|
| `Sleeping`             | Indicates whether the system is asleep.             | `True` / `False`    | `ScheduledSleep`, `ManualSleep`, `ScheduledWake`, `ManualWake` |
| `Transitioning`        | Indicates if a sleep or wake operation is in progress. | `True` / `False`    | `ScalingDown`, `ScalingUp`    |
| `ManualOverride` | Indicates if the current state was triggered manually. | `True` / `False`    | `UserRequest`, `NoManualOverride` |
| `Error`                | Captures failures during operations.               | `True` / `False`    | `ScaleFailed`, `IngressUpdateFailed`, `NoError` |

---

## Condition Details

### `Sleeping`
- **True**: The specified deployments are scaled down and the ingress is modified to show the sleep page.
- **False**: The deployments are running and ingress is in its original state.
- **Reasons**:
  - `ScheduledSleep`: Sleep was initiated by the schedule.
  - `ManualSleep`: Sleep was manually triggered.
  - `ScheduledWake`: Wake was initiated by the schedule.
  - `ManualWake`: Wake was manually triggered.
  - `InitialValue`: Initial value set for a new sleeo schedule.

### `Transitioning`
- **True**: A sleep or wake operation is in progress.
- **False**: No ongoing operations.
- **Reasons**:
  - `Sleeping`: Deployments are going to sleep.
  - `WakingUp`: Deployments are waking up.
  - `NoTransition`: No transition operation in progress.

### `ManualOverride`
- **True**: The current sleeping or awake state was triggered manually. 
- **False**: The state was set by the schedule.
- **Reasons**:
  - `WakeUp`: Manual wake up action requested the user.
  - `Sleep`: Manual sleep action requested the user.
  - `NoManualOverride`: No manual intervention present.

### `Error`
- **True**: The last operation failed.
- **False**: No errors occurred in the most recent operation.
- **Reasons**:
  - `ScaleFailed`: Failed to scale deployments.
  - `IngressSleepFailed`: Failed to update ingress to sleep page.
  - `IngressWakeUpFailed`: Failed to restore ingress to original state.
  - `NoError`: No errors present.

---

## Example Status with Conditions

```yaml
status:
  conditions:
    - type: Sleeping
      status: "True"
      lastTransitionTime: "2025-02-21T23:00:00Z"
      reason: ScheduledSleep
      message: "Deployments have been scaled down and ingress updated."

    - type: Transitioning
      status: "False"
      lastTransitionTime: "2025-02-21T23:01:00Z"
      reason: NoTransition
      message: "No transition in progress."

    - type: ManualOverride
      status: "False"
      lastTransitionTime: "2025-02-21T23:02:00Z"
      reason: NoManualOverride
      message: "No manual override present."

    - type: Error
      status: "False"
      lastTransitionTime: "2025-02-21T23:01:00Z"
      reason: NoError
```

---

## Condition Lifecycle Overview

### Sleep Flow (Scheduled)
1. Set `Transitioning=True` with `reason=ScalingDown`.
2. Scale down deployments and update ingress.
3. Set `Sleeping=True`, `Transitioning=False` with `reason=ScheduledSleep`.

### Wake Flow (Manual)
1. User triggers wake via web endpoint.
2. Set `ManualOverrideActive=True` and `Transitioning=True` with `reason=ScalingUp`.
3. Scale up deployments and restore ingress.
4. Set `Sleeping=False`, `Transitioning=False` with `reason=ManualWake`.
5. Set `ManualOverrideActive=False`.

### Error Handling
- If an error occurs during sleep or wake:
  - Set `Error=True` with an appropriate `reason` and `message`.
  - `Transitioning=False` indicates the operation stopped.

---

## Notes
- `lastTransitionTime` reflects when the condition last changed.
- Only one of `Sleeping=True` or `Sleeping=False` should be `True` at any time.
- `Transitioning=True` indicates in-progress operations and should be `False` otherwise.
- `ManualOverrideActive=True` persists until the next scheduled state change unless cleared.
- `Error=True` should reset to `False` after a successful subsequent operation.

