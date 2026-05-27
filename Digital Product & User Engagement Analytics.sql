/*******************************************************************************
PROJECT: Digital Product & User Engagement Analytics
AUTHOR: [Your Name]
DATE: May 2026
DESCRIPTION: This project analyzes user event streams, session metrics, and 
             subscription data to identify product friction points, measure app 
             stickiness, and discover features that minimize customer churn.
*******************************************************************************/

-- ==========================================
-- STEP 1: DATABASE SETUP & ENVIRONMENT
-- ==========================================

-- Drop tables if they exist to ensure reproducibility
DROP TABLE IF EXISTS user_events;
DROP TABLE IF EXISTS subscription_data;

-- Create the subscription status table (SaaS / Customer profile data)
CREATE TABLE subscription_data (
    customer_id VARCHAR(50) PRIMARY KEY,
    subscription_type VARCHAR(50),
    multi_device_access VARCHAR(3), -- 'Yes' or 'No'
    monthly_charges NUMERIC(6, 2),
    churn_status INT               -- 1 = Churned, 0 = Active
);

-- Create the granular product event log table
CREATE TABLE user_events (
    event_id SERIAL PRIMARY KEY,
    user_id VARCHAR(50),
    event_name VARCHAR(100),       -- 'land_page', 'create_account', 'complete_profile', 'stream_content'
    event_timestamp TIMESTAMP,
    device_type VARCHAR(50)
);


-- ==========================================
-- STEP 2: MOCK DATA POPULATION 
-- (Simulating Kaggle event data structures)
-- ==========================================

INSERT INTO subscription_data (customer_id, subscription_type, multi_device_access, monthly_charges, churn_status) VALUES
('USR001', 'Premium', 'Yes', 14.99, 0),
('USR002', 'Basic',   'No',  8.99,  1),
('USR003', 'Standard', 'Yes', 11.99, 0),
('USR004', 'Basic',   'No',  8.99,  1),
('USR005', 'Premium', 'Yes', 14.99, 0),
('USR006', 'Standard', 'No',  11.99, 1),
('USR007', 'Premium', 'Yes', 14.99, 0);

INSERT INTO user_events (user_id, event_name, event_timestamp, device_type) VALUES
-- User 1 complete funnel journey
('USR001', 'land_page',        '2026-05-01 08:00:00', 'Mobile'),
('USR001', 'create_account',   '2026-05-01 08:05:00', 'Mobile'),
('USR001', 'complete_profile', '2026-05-01 08:10:00', 'Mobile'),
('USR001', 'stream_content',   '2026-05-01 19:30:00', 'TV'),
('USR001', 'stream_content',   '2026-05-02 12:00:00', 'Mobile'), -- Returning activity day 2

-- User 2 drops off at profile completion
('USR002', 'land_page',        '2026-05-01 09:15:00', 'Desktop'),
('USR002', 'create_account',   '2026-05-01 09:22:00', 'Desktop'),

-- User 3 complete funnel journey
('USR003', 'land_page',        '2026-05-01 10:00:00', 'Mobile'),
('USR003', 'create_account',   '2026-05-01 10:04:00', 'Mobile'),
('USR003', 'complete_profile', '2026-05-01 10:12:00', 'Mobile'),
('USR003', 'stream_content',   '2026-05-15 14:00:00', 'Mobile'), -- Returning activity later in month

-- User 4 drops off immediately after landing
('USR004', 'land_page',        '2026-05-01 11:30:00', 'Desktop'),

-- User 5 complete funnel journey
('USR005', 'land_page',        '2026-05-01 14:00:00', 'Mobile'),
('USR005', 'create_account',   '2026-05-01 14:05:00', 'Mobile'),
('USR005', 'complete_profile', '2026-05-01 14:15:00', 'Mobile'),
('USR005', 'stream_content',   '2026-05-01 15:00:00', 'Mobile');


-- ==========================================
-- STEP 3: CORE PORTFOLIO ANALYSIS QUERIES
-- ==========================================

-------------------------------------------------------------------------------
-- METRIC 1: App Stickiness (DAU / MAU Ratio)
-- Business Value: Measures user retention and how habit-forming the product is.
-- Higher percentages imply users engage with the app daily, rather than monthly.
-------------------------------------------------------------------------------

WITH daily_active_users AS (
    -- Calculate unique active users for each specific day
    SELECT 
        DATE(event_timestamp) AS activity_date,
        COUNT(DISTINCT user_id) AS dau
    FROM user_events
    GROUP BY 1
),
monthly_active_users AS (
    -- Calculate unique active users over the entire broad month
    SELECT 
        DATE_TRUNC('month', event_timestamp) AS activity_month,
        COUNT(DISTINCT user_id) AS mau
    FROM user_events
    GROUP BY 1
)
SELECT 
    d.activity_date,
    d.dau,
    m.mau,
    -- Safely convert integers to decimal values to avoid truncation bugs
    ROUND((d.dau::NUMERIC / m.mau) * 100, 2) AS stickiness_percentage
FROM daily_active_users d
JOIN monthly_active_users m 
  ON DATE_TRUNC('month', d.activity_date) = m.activity_month
ORDER BY d.activity_date;


-------------------------------------------------------------------------------
-- METRIC 2: Conversion Funnel & Drop-off Analysis
-- Business Value: Pinpoints user friction during onboarding. Shows product
-- managers exactly where UI or operational drop-off occurs.
-------------------------------------------------------------------------------

WITH user_milestones AS (
    -- Pivot event actions into distinct flag checkpoints per user
    SELECT 
        user_id,
        MAX(CASE WHEN event_name = 'land_page' THEN 1 ELSE 0 END) AS hit_landing,
        MAX(CASE WHEN event_name = 'create_account' THEN 1 ELSE 0 END) AS created_acct,
        MAX(CASE WHEN event_name = 'complete_profile' THEN 1 ELSE 0 END) AS finished_profile
    FROM user_events
    GROUP BY user_id
)
SELECT 
    SUM(hit_landing) AS total_visitors,
    SUM(created_acct) AS total_signups,
    SUM(finished_profile) AS total_onboarded,
    
    -- Drop-off Step 1: Users who saw landing page but failed to create an account
    ROUND((1 - (SUM(created_acct)::NUMERIC / SUM(hit_landing))) * 100, 2) AS landing_to_signup_drop_pct,
    
    -- Drop-off Step 2: Users who signed up but walked away before finalizing profile details
    ROUND((1 - (SUM(finished_profile)::NUMERIC / SUM(created_acct))) * 100, 2) AS signup_to_profile_drop_pct
FROM user_milestones;


-------------------------------------------------------------------------------
-- METRIC 3: Feature Interaction vs. User Attrition (Churn Analysis)
-- Business Value: Identifies correlation between plan structures and cross-device
-- flexibility to find out which demographics generate highly volatile churn risk.
-------------------------------------------------------------------------------

SELECT 
    subscription_type,
    multi_device_access,
    COUNT(customer_id) AS total_users,
    SUM(churn_status) AS total_churned_users,
    
    -- Calculate the exact percentage of lost accounts within each user tier
    ROUND((SUM(churn_status)::NUMERIC / COUNT(customer_id)) * 100, 2) AS churn_rate_percentage
FROM subscription_data
GROUP BY subscription_type, multi_device_access
ORDER BY churn_rate_percentage DESC;