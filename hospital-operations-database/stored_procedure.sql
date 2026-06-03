-- Hospital Operations Management Database
-- Stored procedure: automated quality-indicator reporting
-- (synthesized data; no real patient information)
--
-- ComputeQualityIndicators(p_start_date, p_end_date)
-- Computes four quality indicators for a reporting period and writes them
-- into the quality_indicators reporting table. Clears prior results for the
-- same period to prevent duplicate rows on rerun.
--
-- Indicators:
--   readmission_rate_30d              30-day readmission rate by catchment area
--   first_encounter_complication_rate first encounter ED/inpatient, by catchment area
--   bed_utilization_rate              inpatient bed-days vs. capacity, by department
--   provider_workload_index           encounters per active staff-day, by department

DROP PROCEDURE IF EXISTS ComputeQualityIndicators;

DELIMITER //

CREATE PROCEDURE ComputeQualityIndicators(
  IN p_start_date DATE,
  IN p_end_date   DATE
)
BEGIN
  DECLARE v_computation_date DATE;
  DECLARE v_days_in_period   INT;

  -- Validate reporting period
  IF p_start_date IS NULL OR p_end_date IS NULL OR p_start_date > p_end_date THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Invalid reporting period';
  END IF;

  -- Procedure-level values used across all indicators
  SET v_computation_date = CURDATE();
  SET v_days_in_period   = DATEDIFF(p_end_date, p_start_date) + 1;

  -- Remove prior indicators for the selected period
  DELETE FROM quality_indicators
  WHERE ReportingPeriodStart = p_start_date
    AND ReportingPeriodEnd   = p_end_date
    AND IndicatorID > 0;

  -- Insert all computed indicators
  INSERT INTO quality_indicators
    (DepartmentID, CatchmentArea, IndicatorName, ReportingPeriodStart,
     ReportingPeriodEnd, Numerator, Denominator, ComputedValue, SeverityFlag,
     ComputationDate, DerivationRule)
  SELECT q.DepartmentID, q.CatchmentArea, q.IndicatorName, p_start_date, p_end_date,
         q.Numerator, q.Denominator, q.ComputedValue,
         IF(q.ComputedValue > q.CriticalCutoff, 'critical',
            IF(q.ComputedValue > q.ElevatedCutoff, 'elevated', 'normal')),
         v_computation_date, q.DerivationRule
  FROM (

    -- 1. Readmission rate by catchment area
    SELECT NULL AS DepartmentID, p.CatchmentArea,
           'readmission_rate_30d' AS IndicatorName,
           SUM(IF(e.IsReadmission = 'Yes', 1, 0)) AS Numerator,
           COUNT(*) AS Denominator,
           ROUND(SUM(IF(e.IsReadmission = 'Yes', 1, 0)) * 100 / COUNT(*), 1) AS ComputedValue,
           10 AS CriticalCutoff,
           5  AS ElevatedCutoff,
           'Readmissions / inpatient+ED encounters per catchment area' AS DerivationRule
    FROM encounters e
    JOIN patients p ON e.PatientID = p.PatientID
    WHERE e.EncounterType IN ('inpatient', 'emergency')
      AND e.EncounterDate BETWEEN p_start_date AND p_end_date
    GROUP BY p.CatchmentArea

    UNION ALL

    -- 2. First-encounter complication rate by catchment area
    SELECT NULL AS DepartmentID, p.CatchmentArea,
           'first_encounter_complication_rate' AS IndicatorName,
           SUM(IF(first_e.EncounterType IN ('emergency', 'inpatient'), 1, 0)) AS Numerator,
           COUNT(*) AS Denominator,
           ROUND(SUM(IF(first_e.EncounterType IN ('emergency', 'inpatient'), 1, 0)) * 100 / COUNT(*), 1) AS ComputedValue,
           50 AS CriticalCutoff,
           30 AS ElevatedCutoff,
           'Patients whose first encounter is emergency/inpatient per catchment' AS DerivationRule
    FROM (
      -- first encounter per patient in the reporting period
      SELECT e.PatientID, e.EncounterType,
             ROW_NUMBER() OVER (PARTITION BY e.PatientID ORDER BY e.EncounterDate) AS rn
      FROM encounters e
      WHERE e.EncounterDate BETWEEN p_start_date AND p_end_date
    ) first_e
    JOIN patients p ON first_e.PatientID = p.PatientID
    WHERE first_e.rn = 1
    GROUP BY p.CatchmentArea

    UNION ALL

    -- 3. Bed utilization rate by department
    SELECT d.DepartmentID, NULL AS CatchmentArea,
           'bed_utilization_rate' AS IndicatorName,
           SUM(e.LengthOfStayDays) AS Numerator,
           d.BedCapacity * v_days_in_period AS Denominator,
           ROUND(SUM(e.LengthOfStayDays) * 100 / (d.BedCapacity * v_days_in_period), 2) AS ComputedValue,
           85 AS CriticalCutoff,
           70 AS ElevatedCutoff,
           'Total bed-days used / (bed capacity x days in period) per department' AS DerivationRule
    FROM encounters e
    JOIN departments d ON e.DepartmentID = d.DepartmentID
    WHERE e.EncounterType = 'inpatient'
      AND e.LengthOfStayDays > 0
      AND d.BedCapacity > 0
      AND e.EncounterDate BETWEEN p_start_date AND p_end_date
    GROUP BY d.DepartmentID, d.DepartmentName, d.BedCapacity

    UNION ALL

    -- 4. Provider workload index by department
    SELECT enc_counts.DepartmentID, NULL AS CatchmentArea,
           'provider_workload_index' AS IndicatorName,
           enc_counts.EncounterCount AS Numerator,
           active_staff.StaffCount * v_days_in_period AS Denominator,
           ROUND(enc_counts.EncounterCount * 1 / (active_staff.StaffCount * v_days_in_period), 4) AS ComputedValue,
           0.5 AS CriticalCutoff,
           0.3 AS ElevatedCutoff,
           'Encounters / (active clinical staff x days in period) per department' AS DerivationRule
    FROM (
      -- encounters by department during the reporting period
      SELECT DepartmentID, COUNT(*) AS EncounterCount
      FROM encounters
      WHERE EncounterDate BETWEEN p_start_date AND p_end_date
      GROUP BY DepartmentID
    ) enc_counts
    JOIN (
      -- active clinical staff during the reporting period
      SELECT DepartmentID, COUNT(*) AS StaffCount
      FROM staff
      WHERE EmploymentStatus = 'active'
        AND Role IN ('resident', 'nurse', 'specialist', 'consultant')
      GROUP BY DepartmentID
    ) active_staff
      ON enc_counts.DepartmentID = active_staff.DepartmentID

  ) q;

END //

DELIMITER ;

-- Execute the procedure and view the results
CALL ComputeQualityIndicators('2024-01-01', '2025-12-31');

SELECT qi.IndicatorName,
       IFNULL(qi.CatchmentArea, '-')  AS CatchmentArea,
       IFNULL(d.DepartmentName, '-')  AS DepartmentName,
       qi.Numerator, qi.Denominator, qi.ComputedValue, qi.SeverityFlag
FROM quality_indicators qi
LEFT JOIN departments d ON qi.DepartmentID = d.DepartmentID
ORDER BY qi.IndicatorName, COALESCE(qi.CatchmentArea, ''), d.DepartmentName;
