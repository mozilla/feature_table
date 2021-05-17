DECLARE start_date DATE DEFAULT '2021-01-01';

CREATE OR REPLACE TABLE
  `mozdata`.analysis.csl_feature_set_v1
PARTITION BY submission_date
AS

WITH user_type as (
SELECT
  cls.client_id,
  cls.submission_date,
  cls.activity_segments_v1,
  cls.is_allweek_regular_v1,
  cls.is_weekday_regular_v1,
  cls.is_core_active_v1,
  cls.days_since_first_seen,
  cls.days_since_seen,
  cls.new_profile_7_day_activated_v1,
  cls.new_profile_14_day_activated_v1,
  cls.new_profile_21_day_activated_v1,
  cls.first_seen_date,
  cls.days_since_created_profile,
  cls.profile_creation_date,
  cls.country,
  cls.scalar_parent_os_environment_is_taskbar_pinned,
  cls.scalar_parent_os_environment_launched_via_desktop,
  cls.scalar_parent_os_environment_launched_via_other,
  cls.scalar_parent_os_environment_launched_via_taskbar,
  cls.scalar_parent_os_environment_launched_via_start_menu,
  cls.scalar_parent_os_environment_launched_via_other_shortcut,
  cls.os,
  cls.normalized_os_version,
  cls.app_version,
  
  # I split the attribution data into multiple fields. do we care about the string values of any of the attribution fields besides medium and campaign?
  
  # [@shong] I think the only attribution data we should include is attributed vs non-attributed
  # [@shong] the actual values of attribution in Telemetry are transformed and not don't accurate represent the information
  # [@shong] see: ISSUE: GA to Telemetry Attribution Passing Consistency: https://docs.google.com/document/d/112k76fWVWEV23bILg_RReiZEvFIXDlMH9w_yUwNYIGc/edit
  # [@shong] removed: attribution_source, attribution_campaign, attribution_paid, and attribution_unpaid
  
  (cls.attribution.campaign IS NOT NULL) OR (cls.attribution.source IS NOT NULL) AS attributed,
  cls.is_default_browser,
  cls.sync_count_desktop_mean,
  cls.sync_count_mobile_mean,
  cls.active_hours_sum,
  cls.subsession_hours_sum
  scalar_parent_browser_engagement_total_uri_count_sum,
  ad_clicks_count_all,
  scalar_parent_browser_engagement_tab_open_event_count_sum,
  scalar_parent_browser_engagement_window_open_event_count_sum,
  scalar_parent_browser_engagement_unique_domains_count_max,
  scalar_parent_browser_engagement_unique_domains_count_mean,
  scalar_parent_browser_engagement_max_concurrent_tab_count_max,
  scalar_parent_browser_engagement_max_concurrent_window_count_max,
  search_count_abouthome,
  search_count_all,
  search_count_contextmenu,
  search_count_newtab,
  search_count_organic,
  search_count_searchbar,
  search_count_system,
  search_count_tagged_follow_on,
  search_count_tagged_sap,
  search_count_urlbar,
  search_with_ads_count_all,
  
  # [@shong] active_addons_count_mean, I believe this just counts all addons including stuff we have behind the 
  # [@shong] curtain, system addons and such, and is not representative of the user added addons. 
  # [@shong] I'm not sure we want to include this as it's really noisy, and might just distinguish between
  # [@shong] different versions of Firefox (with different system addon states) then any user behavior or 
  # [@shong] feature interaction we're interested in. I know there's an established methodology for determining
  # [@shong] which addons are user added or not, maybe we should just provide that (user added addons)?
  # [@shong] removed: active_addons_count_mean
  
  # [@shong] I don't think we should include the PLACES_BOOKMARKS_COUNT measurement since we know this
  # [@shong] this telemetry is buggy (it's a state measurement that isn't always recorded when it should be, 
  # [@shong] and it's unclear what conditions trigger it. Most likely a race condition of some kind, since 
  # [@shong] PLACES module is really old and requires a lot of I/O). I don't think we should include it without
  # [@shong] doing some due diligence and a decision point on if we believe this is reliable or not. 
  # [@shong] see: https://colab.research.google.com/drive/1DzveSb7eqwIjxt1Ve_V0T8ROtPt6Dw8w#scrollTo=gRb0NXzKLLBX
  # [@shong] removed: places_bookmarks_count_mean


FROM `moz-fx-data-shared-prod.telemetry.clients_last_seen` cls
WHERE cls.submission_date > start_date
    AND cls.sample_id = 0
    AND cls.normalized_channel = 'release'
    # added this - is it needed?
    AND days_since_seen = 0
),

main as (
SELECT
  client_id,
  MOD(ABS(FARM_FINGERPRINT(client_id)), 100) AS subsample_id,
  DATE(submission_timestamp) AS submission_date,
  LOGICAL_OR(COALESCE(environment.system.gfx.headless, false)) as is_headless,
  SUM(COALESCE(CAST(JSON_EXTRACT_SCALAR(payload.processes.content.histograms.video_play_time_ms, '$.sum') AS int64), 0)) AS video_play_time_ms,
  SUM(COALESCE(CAST(JSON_EXTRACT_SCALAR(payload.processes.content.histograms.video_encrypted_play_time_ms, '$.sum') AS int64), 0)) AS video_encrypted_play_time_ms,
  SUM(COALESCE(CAST(JSON_EXTRACT_SCALAR(payload.processes.content.histograms.pdf_viewer_time_to_view_ms, '$.sum') AS int64), 0)) AS pdf_viewer_time_to_view_ms_content,
  SUM(COALESCE(CAST(JSON_EXTRACT_SCALAR(payload.histograms.fx_picture_in_picture_window_open_duration, '$.sum') AS int64), 0)) AS pip_window_open_duration,
  SUM(COALESCE((SELECT SUM(value) FROM UNNEST(mozfun.hist.extract(payload.processes.content.histograms.video_play_time_ms).values)), 0)) AS video_play_time_ms_count,
  SUM(COALESCE((SELECT SUM(value) FROM UNNEST(mozfun.hist.extract(payload.processes.content.histograms.video_encrypted_play_time_ms).values)), 0)) AS video_encrypted_play_time_ms_count,
  SUM(COALESCE((SELECT SUM(value) FROM UNNEST(mozfun.hist.extract(payload.processes.content.histograms.pdf_viewer_time_to_view_ms).values)), 0)) AS pdf_viewer_time_to_view_ms_content_count,
  SUM(COALESCE((SELECT SUM(value) FROM UNNEST(mozfun.hist.extract(payload.histograms.fx_picture_in_picture_window_open_duration).values)), 0)) AS pip_window_open_duration_count,
  SUM(COALESCE(CAST(JSON_EXTRACT_SCALAR(payload.histograms.pdf_viewer_document_size_kb, '$.sum') AS int64), 0)) AS pdf_viewer_doc_size_kb,
  SUM(COALESCE(CAST(JSON_EXTRACT_SCALAR(payload.processes.content.histograms.pdf_viewer_document_size_kb, '$.sum') AS int64), 0)) AS pdf_viewer_doc_size_kb_content,
  SUM(COALESCE((SELECT SUM(value) FROM UNNEST(mozfun.hist.extract(payload.histograms.pdf_viewer_document_size_kb).values)), 0)) AS pdf_viewer_doc_size_kb_count,
  SUM(COALESCE((SELECT SUM(value) FROM UNNEST(mozfun.hist.extract(payload.processes.content.histograms.pdf_viewer_document_size_kb).values)), 0)) AS pdf_viewer_doc_size_kb_content_count,
  COUNTIF(COALESCE(environment.services.account_enabled, FALSE)) > 0 AS sync_signed_in,
  COUNTIF(COALESCE(payload.processes.parent.scalars.formautofill_credit_cards_autofill_profiles_count IS NOT NULL, FALSE)) > 0 AS ccards_saved,
  COUNTIF(COALESCE(payload.processes.parent.scalars.dom_parentprocess_private_window_used, FALSE)) > 0 AS pbm_used,
  
  # [@shong] the imports query is actually wrong - the histograms include imports from profile refreshes (aka profile resets) 
  # [@shong] which is where a lot of these import events are coming from. These are indicated by source: Firefox, but it needs 
  # [@shong] to be filtered out. See: https://colab.research.google.com/drive/1yauD-2JcfvvFt_P87JfzSQ0tCEWHTZ4w
  # [@shong] also, I think the histogram might have bins even if there are no items imported, so we should be checking
  # [@shong] if the values are greater then 0, not array length. 
  # [@shong] I'll add the correct query to this later (not sure if I can do it in this iteration, but put that action item on me) 
  # [@shong] removed: imported_history, imported_bookmarks, imported_logins

  # [@shong] so the pinned_tab_count_count had a bug with recording (it was only recording when a new pin / unpin action happened, 
  # [@shong] not recording state), see: https://bugzilla.mozilla.org/show_bug.cgi?id=1639292 
  # [@shong] so it looks like it got resolved, but it's not clear to me from the comments if the telemetry is doing exactly what we
  # [@shong] think it does, or something similar. We should follow up to confirm exact behavior currently before adding. 
  # [@shong] I've ping'd andrei for clarification. 
  # [@shong] removed: pinned_tab_count_count

  # [@shong] browser_ui_* telemetry, I'm not sure any due diligence has been done on these. I designed this telemetry but there's 
  # [@shong] but there's been no followup validation of behavior AFAIK. Note - this was implemented as semi-unstructured telemetry design, so
  # [@shong] we didn't really know exactly what the behavior will be when we implemented it. 
  # [@shong] lets remove until we do some validation and documentation on this family of telemetry so we can confirm it behaves as we're assuming
  # [@shong] it does. 
  # [@shong] removed: unique_preferences_accessed_count, preferences_accessed_total, unique_bookmarks_bar_accessed_count, 
  # [@shong]          bookmarks_bar_accessed_total, keyboard_shortcut_total, keyboard_shortcut_total

  SUM(COALESCE(ARRAY_LENGTH(payload.processes.parent.keyed_scalars.sidebar_opened), 0)) AS unique_sidebars_accessed_count,
  SUM(COALESCE((SELECT SUM(value) FROM UNNEST(payload.processes.parent.keyed_scalars.sidebar_opened)), 0)) AS sidebars_accessed_total,
  SUM(COALESCE(ARRAY_LENGTH(payload.processes.parent.keyed_scalars.urlbar_picked_history), 0)) AS unique_history_urlbar_indices_picked_count,
  SUM(COALESCE((SELECT SUM(value) FROM UNNEST(payload.processes.parent.keyed_scalars.urlbar_picked_history)), 0)) AS history_urlbar_picked_total,
  SUM(COALESCE(ARRAY_LENGTH(payload.processes.parent.keyed_scalars.urlbar_picked_remotetab), 0)) AS unique_remotetab_indices_picked_count,
  SUM(COALESCE((SELECT SUM(value) FROM UNNEST(payload.processes.parent.keyed_scalars.urlbar_picked_remotetab)), 0)) AS remotetab_picked_total,

  # [@shong] see note on browser_ui_* above 

  SUM(COALESCE((SELECT SUM(value) FROM UNNEST(payload.processes.parent.keyed_scalars.browser_engagement_navigation_about_newtab)), 0)) AS uris_from_newtab,
  SUM(COALESCE((SELECT SUM(value) FROM UNNEST(payload.processes.parent.keyed_scalars.browser_engagement_navigation_searchbar)), 0)) AS uris_from_searchbar,
  SUM(COALESCE((SELECT SUM(value) FROM UNNEST(payload.processes.parent.keyed_scalars.browser_engagement_navigation_urlbar)), 0)) AS uris_from_urlbar,
  SUM(COALESCE(`moz-fx-data-shared-prod.udf.get_key`(`moz-fx-data-shared-prod.udf.json_extract_histogram`(payload.histograms.fx_urlbar_selected_result_type_2).values, 2), 0)) AS nav_history_urlbar,
  SUM(COALESCE(`moz-fx-data-shared-prod.udf.get_key`(`moz-fx-data-shared-prod.udf.json_extract_histogram`(payload.histograms.fx_urlbar_selected_result_type_2).values, 0), 0)) AS nav_autocomplete_urlbar,
  SUM(COALESCE(`moz-fx-data-shared-prod.udf.get_key`(`moz-fx-data-shared-prod.udf.json_extract_histogram`(payload.histograms.fx_urlbar_selected_result_type_2).values, 8), 0)) AS nav_visiturl_urlbar,
  SUM(COALESCE(`moz-fx-data-shared-prod.udf.get_key`(`moz-fx-data-shared-prod.udf.json_extract_histogram`(payload.histograms.fx_urlbar_selected_result_type_2).values, 5), 0)) AS nav_searchsuggestion_urlbar,
  SUM(COALESCE(`moz-fx-data-shared-prod.udf.get_key`(`moz-fx-data-shared-prod.udf.json_extract_histogram`(payload.histograms.fx_urlbar_selected_result_type_2).values, 13), 0)) AS nav_topsite_urlbar,
  MAX(COALESCE(CAST(JSON_EXTRACT_SCALAR(payload.histograms.pwmgr_num_saved_passwords, '$.sum') AS int64), 0)) AS num_passwords_saved
FROM `moz-fx-data-shared-prod.telemetry.main_1pct`
WHERE
    DATE(submission_timestamp) > start_date
    AND sample_id = 0
    AND normalized_channel = 'release'
GROUP BY submission_date, client_id
),


events as (
SELECT
  e.client_id,
  e.submission_date,
  COALESCE(COUNTIF(event_category = 'pictureinpicture' AND event_method =  'create'), 0) AS pip_count,
  COALESCE(COUNTIF(event_category = 'security.ui.protections' AND event_object = 'protection_report'), 0) AS viewed_protection_report_count,
  COUNTIF(event_category = 'security.ui.protectionspopup' AND event_object = 'etp_toggle_off') AS etp_toggle_off,
  COUNTIF(event_category = 'security.ui.protectionspopup' AND event_object = 'etp_toggle_on') AS etp_toggle_on,
  COUNTIF(event_category = 'security.ui.protectionspopup' AND event_object = 'protections_popup') AS protections_popup,
  COALESCE(COUNTIF(event_category = 'creditcard' AND event_object = 'cc_form' AND event_method = 'filled'), 0) AS ccard_filled,
  COALESCE(COUNTIF(event_category = 'creditcard' AND event_object = 'capture_doorhanger' AND event_method = 'save'), 0) AS ccard_saved,
  COALESCE(COUNTIF(event_method = 'install' AND event_category = 'addonsManager' AND event_object = 'extension'), 0) AS installed_extension,
  COALESCE(COUNTIF(event_method = 'install' AND event_category = 'addonsManager' AND event_object = 'theme'), 0) AS installed_theme,
  COALESCE(COUNTIF(event_method = 'install' AND event_category = 'addonsManager' AND event_object IN ('dictionary', 'locale')), 0) AS installed_l10n,
  COALESCE(COUNTIF(event_method = 'saved_login_used'), 0) AS used_stored_pw,
  COALESCE(COUNTIF(event_category = 'pwmgr' AND event_object IN ('form_login', 'form_password', 'auth_login', 'prompt_login')), 0) AS password_filled,
  COALESCE(COUNTIF(event_category = 'pwmgr' AND event_method = 'doorhanger_submitted' AND event_object = 'save'), 0) AS password_saved,
  COALESCE(COUNTIF(event_category = 'pwmgr' AND event_method = 'open_management'), 0) AS pwmgr_opened,
  COALESCE(COUNTIF(event_category = 'pwmgr' AND event_method IN ('copy', 'show')), 0) AS pwmgr_copy_or_show_info,
  COALESCE(COUNTIF(event_category = 'pwmgr' AND event_method IN ('dismiss_breach_alert', 'learn_more_breach')), 0) AS pwmgr_interacted_breach,
  COALESCE(COUNTIF(event_object = 'generatedpassword' AND event_method = 'autocomplete_field'), 0) AS generated_password,
#   Leif we should do some research on when these events are fired. EG bmks, which adding methods are we getting with this event.
  COALESCE(COUNTIF(event_category = 'activity_stream' AND event_object IN ('CLICK') ), 0) AS newtab_click,
  COALESCE(COUNTIF(event_category = 'activity_stream' AND event_object IN ('BOOKMARK_ADD') ), 0) AS bookmark_added_from_newtab,
  COALESCE(COUNTIF(event_category = 'activity_stream' AND event_object IN ('SAVE_TO_POCKET') ), 0) AS saved_to_pocket_from_newtab,
  COALESCE(COUNTIF(event_category = 'activity_stream' AND event_object IN ('OPEN_NEWTAB_PREFS') ), 0) AS newtab_prefs_opened,
  COALESCE(COUNTIF(event_category = 'fxa' AND event_method = 'connect' ), 0) AS fxa_connect,
  COALESCE(COUNTIF(event_category = 'normandy' AND event_object IN ("preference_study", "addon_study", "preference_rollout", "addon_rollout") ), 0) AS normandy_enrolled,
  COALESCE(COUNTIF(event_category = 'messaging_experiments' AND event_method = 'reach'), 0) AS cfr_qualified,
  COALESCE(COUNTIF(event_category = 'downloads'), 0) AS downloads,
  COALESCE(COUNTIF(event_category = 'downloads' AND event_string_value = 'pdf'), 0) AS pdf_downloads,
  COALESCE(COUNTIF(event_category = 'downloads' AND event_string_value IN ('jpg', 'jpeg', 'png', 'gif')), 0) AS image_downloads,
  COALESCE(COUNTIF(event_category = 'downloads' AND event_string_value IN ('mp4', 'mp3', 'wav', 'mov')), 0) AS media_downloads,
  COALESCE(COUNTIF(event_category = 'downloads' AND event_string_value IN ('xlsx', 'docx', 'pptx', 'xls', 'ppt', 'doc')), 0) AS msoffice_downloads
FROM `moz-fx-data-shared-prod.telemetry.events` e
WHERE e.submission_date > start_date
  AND e.sample_id = 0
  AND e.normalized_channel = 'release'
GROUP BY 1, 2
),
           
activity_stream_events as (
  SELECT
    client_id,
    DATE(submission_timestamp) as submission_date,
    COALESCE(LOGICAL_OR(CASE WHEN event = 'PAGE_TAKEOVER_DATA' THEN true ELSE false END), false) as newtab_switch, 
    COALESCE(COUNTIF(event = 'CLICK' AND source = 'TOP_SITES'), 0) as topsite_clicks,
    COALESCE(COUNTIF(event = 'CLICK' AND source = 'HIGHLIGHTS'), 0) as highlight_clicks
  FROM `moz-fx-data-shared-prod`.activity_stream.events
  WHERE DATE(submission_date) > start_date
    AND sample_id = 0
    AND normalized_channel = 'release'
  ),
           
activity_stream_sessions as (
  SELECT
    client_id,
    DATE(submission_timestamp) as submission_date,
    COALESCE(MAX(user_prefs & 1 = 0), false) as turned_off_newtab_search,
    COALESCE(MAX(user_prefs & 2 = 0), false) as turned_off_topsites,
    COALESCE(MAX(user_prefs & 4 = 0), false) as turned_off_pocket,
    COALESCE(MAX(user_prefs & 8 = 0), false) as turned_off_highlights
  FROM  `moz-fx-data-shared-prod.activity_stream.sessions`
  WHERE DATE(submission_date) > start_date
    AND sample_id = 0
    AND normalized_channel = 'release'
  ),

addons as (
  SELECT
    client_id,
    submission_date,
    SUM(CASE WHEN addon_id IN ('uBlock0@raymondhill.net',                /* uBlock Origin */
                             '{d10d0bf8-f5b5-c8b4-a8b2-2b9879e08c5d}', /* Adblock Plus */
                             'jid1-NIfFY2CA8fy1tg@jetpack',            /* Adblock */
                             '{73a6fe31-595d-460b-a920-fcc0f8843232}', /* NoScript */
                             'firefox@ghostery.com',                   /* Ghostery */
                             'adblockultimate@adblockultimate.net',    /* AdBlocker Ultimate */
                             'jid1-MnnxcxisBPnSXQ@jetpack'             /* Privacy Badger */)
            THEN 1
            ELSE 0
          END ) AS num_addblockers,
    # any kind of themes?
    # be sure to include VPN and other mozilla owned extensions
    LOGICAL_OR(COALESCE(addon_id = 'notes@mozilla.com', FALSE)) AS has_notes_extension,
    LOGICAL_OR(COALESCE(addon_id = '@contain-facebook', FALSE)) AS has_facebook_container_extension,
    LOGICAL_OR(COALESCE(addon_id = '@testpilot-containers', FALSE)) AS has_multiaccount_container_extension,
    LOGICAL_OR(COALESCE(addon_id = 'private-relay@firefox.com', FALSE)) AS has_private_relay_extension
  FROM `mozdata.telemetry.addons`
  WHERE submission_date > start_date
    AND sample_id = 0
    AND normalized_channel = 'release'
  GROUP BY 1, 2
),

joined as (
SELECT
  u.*,
  m.* EXCEPT (client_id, submission_date),
  e.* EXCEPT (client_id, submission_date),
  a.* EXCEPT (client_id, submission_date),
  ae.* EXCEPT (client_id, submission_date),
  asp.* EXCEPT (client_id, submission_date)
FROM user_type u
LEFT JOIN main m ON u.client_id = m.client_id AND u.submission_date = m.submission_date
LEFT JOIN events e ON u.client_id = e.client_id AND u.submission_date = e.submission_date
LEFT JOIN addons a ON u.client_id = a.client_id AND u.submission_date = a.submission_date
LEFT JOIN activity_stream_events ase ON u.client_id = ase.client_id AND u.submission_date = ase.submission_date
LEFT JOIN activity_stream_sessions asp ON u.client_id = asp.client_id AND u.submission_date = asp.submission_date
)

SELECT
  *
FROM joined j
