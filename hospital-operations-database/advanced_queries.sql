-- Hospital Operations Management Database
-- Schema extensions and advanced analytical queries
-- (synthesized data; no real patient information)

USE health_ops;

-- =====================================================================
-- Schema extensions: derived columns to support performance measures
-- =====================================================================

-- Extend encounters with derived columns
ALTER TABLE encounters
  ADD COLUMN IsReadmission   VARCHAR(3),
  ADD COLUMN LengthOfStayDays INT;

-- Compute length of stay from discharge and encounter dates
UPDATE encounters
SET LengthOfStayDays = CASE
      WHEN DischargeDate IS NOT NULL THEN DATEDIFF(DischargeDate, EncounterDate)
      ELSE NULL
    END;

-- Set default readmission status
UPDATE encounters SET IsReadmission = 'No'
WHERE EncounterID > 0;

-- Flag encounters occurring within 30 days of a prior inpatient discharge
UPDATE encounters e1
JOIN encounters e2
  ON e1.PatientID = e2.PatientID
 AND e1.EncounterDate >  e2.DischargeDate
 AND e1.EncounterDate <= DATE_ADD(e2.DischargeDate, INTERVAL 30 DAY)
 AND e2.EncounterType = 'inpatient'
 AND e2.DischargeDate IS NOT NULL
SET e1.IsReadmission = 'Yes';

-- Extend patients with catchment area
ALTER TABLE patients
  ADD COLUMN CatchmentArea VARCHAR(20);

-- Map ZIP codes to health service area (HSA) labels
UPDATE patients
SET CatchmentArea = CASE
      WHEN Zip IN ('12307', '12305')          THEN 'HSA-1'
      WHEN Zip IN ('12303', '12304', '12308') THEN 'HSA-2'
      WHEN Zip IN ('12301', '12306', '12302') THEN 'HSA-3'
      ELSE 'Unassigned'
    END;

-- Reporting layer for computed quality indicators
CREATE TABLE quality_indicators (
  IndicatorID         INT NOT NULL AUTO_INCREMENT,
  DepartmentID        INT DEFAULT NULL,
  CatchmentArea       VARCHAR(20) DEFAULT NULL,
  IndicatorName       VARCHAR(50) NOT NULL,
  ReportingPeriodStart DATE NOT NULL,
  ReportingPeriodEnd   DATE NOT NULL,
  Numerator           FLOAT,
  Denominator         FLOAT,
  ComputedValue       FLOAT NOT NULL,
  SeverityFlag        VARCHAR(20),
  ComputationDate     DATE NOT NULL,
  DerivationRule      VARCHAR(200) NOT NULL,
  PRIMARY KEY (IndicatorID),
  FOREIGN KEY (DepartmentID) REFERENCES departments(DepartmentID)
);

-- =====================================================================
-- Advanced query 1 (aggregate):
-- Chronic-disease complication rate by insurance and catchment area
-- =====================================================================
SELECT p.CatchmentArea, e.InsuranceType,
       COUNT(*) AS TotalEncounters,
       SUM(CASE WHEN e.EncounterType IN ('emergency', 'inpatient') THEN 1 ELSE 0 END) AS Complications,
       ROUND(AVG(CASE WHEN e.EncounterType IN ('emergency', 'inpatient') THEN 1 ELSE 0 END) * 100, 1) AS ComplicationPct,
       ROUND(AVG(e.EncounterCost), 2) AS AvgCost
FROM encounters e
JOIN patients p ON e.PatientID = p.PatientID
WHERE LOWER(e.ChiefComplaint) REGEXP
      'diabetic|hypoglycemic|diabetes|hypertens|asthma|heart failure'
GROUP BY p.CatchmentArea, e.InsuranceType
ORDER BY p.CatchmentArea, ComplicationPct DESC;

-- =====================================================================
-- Advanced query 2:
-- Claim denial rate and revenue loss by department
-- =====================================================================
SELECT d.DepartmentName,
       COUNT(*) AS TotalClaims,
       SUM(CASE WHEN bc.ClaimStatus = 'denied' THEN 1 ELSE 0 END) AS DeniedClaims,
       ROUND(SUM(CASE WHEN bc.ClaimStatus = 'denied' THEN 1 ELSE 0 END) * 100 / COUNT(*), 1) AS DenialPct,
       ROUND(SUM(CASE WHEN bc.ClaimStatus = 'denied' THEN bc.BilledAmount ELSE 0 END), 2) AS RevenueLost,
       ROUND(SUM(bc.BilledAmount), 2) AS TotalBilled
FROM billing_claims bc
JOIN encounters e   ON bc.EncounterID = e.EncounterID
JOIN departments d  ON e.DepartmentID = d.DepartmentID
GROUP BY d.DepartmentName
HAVING COUNT(*) >= 5
ORDER BY DenialPct DESC;

-- =====================================================================
-- Advanced query 3 (window function):
-- Top 3 costliest inpatient encounters per department
-- =====================================================================
SELECT DepartmentName, EncounterID, ChiefComplaint, InsuranceType,
       EncounterCost, LengthOfStayDays, CostRank
FROM (
  SELECT d.DepartmentName, e.EncounterID, e.ChiefComplaint, e.InsuranceType,
         e.EncounterCost, e.LengthOfStayDays,
         RANK() OVER (PARTITION BY d.DepartmentName ORDER BY e.EncounterCost DESC) AS CostRank
  FROM encounters e
  JOIN departments d ON e.DepartmentID = d.DepartmentID
  WHERE e.EncounterType = 'inpatient'
    AND e.LengthOfStayDays IS NOT NULL
    AND e.LengthOfStayDays > 0
) ranked
WHERE CostRank <= 3
ORDER BY DepartmentName, CostRank;

-- =====================================================================
-- Complex query using CTEs:
-- Patient-level chronic-disease risk classification
-- =====================================================================

-- Step 1: filter chronic-disease encounters; flag complication / readmission
WITH chronic_encounters AS (
  SELECT e.PatientID, p.CatchmentArea, e.EncounterID, e.InsuranceType,
         e.EncounterCost,
         CASE WHEN e.EncounterType IN ('emergency', 'inpatient') THEN 1 ELSE 0 END AS ComplicationFlag,
         CASE WHEN e.IsReadmission = 'Yes' THEN 1 ELSE 0 END AS ReadmissionFlag
  FROM encounters e
  JOIN patients p ON e.PatientID = p.PatientID
  WHERE LOWER(e.ChiefComplaint) REGEXP
        'diabetic|hypoglycemic|diabetes|hypertens|asthma|heart failure'
),
-- Step 2: aggregate chronic-disease burden to one row per patient
chronic_summary AS (
  SELECT PatientID, CatchmentArea,
         COUNT(*) AS ChronicEncounters,
         SUM(ComplicationFlag) AS ComplicationCount,
         SUM(ReadmissionFlag)  AS ReadmissionCount,
         ROUND(AVG(EncounterCost), 2) AS AvgCost,
         MAX(InsuranceType) AS InsuranceType
  FROM chronic_encounters
  GROUP BY PatientID, CatchmentArea
),
-- Step 3: summarize denied claims per patient
denial_summary AS (
  SELECT ce.PatientID,
         COUNT(*) AS TotalClaims,
         SUM(CASE WHEN LOWER(bc.ClaimStatus) = 'denied' THEN 1 ELSE 0 END) AS DeniedClaims
  FROM chronic_encounters ce
  JOIN billing_claims bc ON ce.EncounterID = bc.EncounterID
  GROUP BY ce.PatientID
)
-- Step 4: join summaries and classify overall risk
SELECT cs.PatientID, cs.CatchmentArea, cs.InsuranceType, cs.ChronicEncounters,
       cs.ComplicationCount, cs.ReadmissionCount, cs.AvgCost,
       COALESCE(ds.TotalClaims, 0)  AS TotalClaims,
       COALESCE(ds.DeniedClaims, 0) AS DeniedClaims,
       CASE
         WHEN cs.ComplicationCount >= 2 THEN 'High'
         WHEN cs.ComplicationCount = 1 AND cs.ReadmissionCount >= 1 THEN 'High'
         WHEN cs.ComplicationCount = 1 OR COALESCE(ds.DeniedClaims, 0) >= 2 THEN 'Moderate'
         ELSE 'Low'
       END AS RiskLevel
FROM chronic_summary cs
LEFT JOIN denial_summary ds ON cs.PatientID = ds.PatientID
ORDER BY FIELD(RiskLevel, 'High', 'Moderate', 'Low'),
         cs.ComplicationCount DESC, cs.AvgCost DESC
LIMIT 20;
