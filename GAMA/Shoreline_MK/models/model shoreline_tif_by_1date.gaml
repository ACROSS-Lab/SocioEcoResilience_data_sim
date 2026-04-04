/**
 * © 2026 [Author Name]. All rights reserved.
 * Multi-Norm Shoreline Dynamics — Sliding Window C
 * Confidential and proprietary.
 */

model tif_shoreline_multinorm

global {
    // === FILE INPUTS ===
    file shoreline_file <- file("../includes/Shoreline_MK_v2.shp");
    file transect_file <- file("../includes/transects.shp");
    directory tif_dir <- directory("../includes/Tif_RGBA/");
    directory csv_dir <- directory("../includes/day1/");

    // === TIF MATCHING ===
    list<string> all_names <- list<string>(tif_dir.contents);
    list<string> tif_names <- all_names
        where (length(each) >= 14 and copy_between(each, length(each) - 4, length(each)) = ".tif");
    list<grid_file> file_list <- [];
    list<string> valid_dates <- [];

    int current_index <- 0;
    grid_file curr_tif;
    field fff;
    string current_day <- "";

    grid_file fixed_tif;
    field first_fff;
    string first_date <- "";

    // Reference TIF for world envelope (must be at class level for alignment)
    grid_file ref_tif <- grid_file("../includes/Tif_RGBA/2022-07-26-03-23-46_S2_49PBT_MYKHE_RGBN.tif");
    geometry shape <- envelope(ref_tif);

    // === MULTI-NORM CONFIG ===
    int n_transects <- 229;
    int window_size <- 20;       // 20 transects = 2 km
    float l0_threshold <- 2.0;   // meters

    // CSV data: csv_dist[mk_number][date] = distance(m)
    map<int, map<string, float>> csv_dist;

    // Baseline per transect
    map<int, float> baseline;
    string baseline_label <- "";

    // Current step
    list<float> current_dd <- [];       // Δd per transect (229 values)
    list<float> current_c_local <- [];  // sliding C per transect (229 values)
    string current_season <- "";
    rgb season_color <- #red;

    // Global indicators
    float current_L0 <- 0.0;
    float current_L1 <- 0.0;
    float current_L2 <- 0.0;
    float current_C <- 0.0;

    // History of C_local curves (saved per season)
    list<list<float>> hist_curves <- [];
    list<string> hist_labels <- [];
    list<rgb> hist_colors <- [];
    string prev_label <- "";

    // =====================
    // INIT
    // =====================
    init {
        create transect from: transect_file;
        create shoreline from: shoreline_file with: [
            day :: copy_between(replace(string(read("date")), "/", "-"), 0, 10)
        ];

        list<string> sl_dates <- remove_duplicates(shoreline collect each.day);
        list<string> matched <- tif_names where (sl_dates contains copy_between(each, 0, 10));

        loop f over: matched {
            file_list <- file_list + [grid_file(tif_dir.path + "/" + f)];
            valid_dates <- valid_dates + [copy_between(f, 0, 10)];
        }

        ask shoreline {
            if !(valid_dates contains day) { do die; }
        }

        if (length(file_list) > 0) {
            first_date <- valid_dates[0];
            fixed_tif <- file_list[0];
            first_fff <- field(fixed_tif);

            do load_csv;
            do compute_baseline;
            do load_current;
        } else {
            fff <- field(matrix<float>([[0.0]]));
            first_fff <- field(matrix<float>([[0.0]]));
            current_day <- "N/A";
            first_date <- "N/A";
        }
    }

    // =====================
    // LOAD CSV FROM day1/
    // =====================
    action load_csv {
        list<string> all_csv <- list<string>(csv_dir.contents);
        list<string> fnames <- all_csv where (length(each) > 4 and copy_between(each, length(each) - 4, length(each)) = ".csv");
        loop fname over: fnames {
            int p <- fname index_of "MK";
            if (p > -1) {
                string mk_str <- copy_between(fname, p + 2, length(fname) - 4);
                int mk <- int(mk_str);
                file fdata <- csv_file(csv_dir.path + "/" + fname, ",");
                matrix data <- matrix(fdata);
                map<string, float> dists;
                loop i from: 1 to: data.rows - 1 {
                    string ds <- string(data[1, i]);
                    if (length(ds) >= 10) {
                        dists[copy_between(ds, 0, 10)] <- float(data[2, i]);
                    }
                }
                csv_dist[mk] <- dists;
            }
        }
        write "Loaded " + string(length(csv_dist)) + " transect CSV files";
    }

    // =====================
    // BASELINE = average of first season
    // =====================
    action compute_baseline {
        int yr <- int(copy_between(first_date, 0, 4));
        int mo <- int(copy_between(first_date, 5, 7));
        string s_start;
        string s_end;
        string s_type;

        if (mo >= 5 and mo <= 10) {
            s_type <- "SW";
            s_start <- string(yr) + "-05";
            s_end <- string(yr) + "-11";
        } else if (mo >= 11) {
            s_type <- "NE";
            s_start <- string(yr) + "-11";
            s_end <- string(yr + 1) + "-05";
        } else {
            s_type <- "NE";
            s_start <- string(yr - 1) + "-11";
            s_end <- string(yr) + "-05";
        }

        baseline_label <- s_type + " " + string(yr);

        loop mk from: 1 to: n_transects {
            if (csv_dist contains_key mk) {
                float total <- 0.0;
                int cnt <- 0;
                loop dkey over: (csv_dist[mk]).keys {
                    if (dkey >= s_start and dkey < s_end) {
                        total <- total + csv_dist[mk][dkey];
                        cnt <- cnt + 1;
                    }
                }
                if (cnt > 0) {
                    baseline[mk] <- total / cnt;
                }
            }
        }
        write "Baseline: " + baseline_label + " (" + string(length(baseline)) + " transects)";
    }

    // =====================
    // SEASON LABEL HELPER
    // =====================
    string season_label_result <- "";

    action compute_season_label (string date_str) {
        int yr <- int(copy_between(date_str, 0, 4));
        int mo <- int(copy_between(date_str, 5, 7));
        if (mo >= 5 and mo <= 10) {
            season_label_result <- "SW " + string(yr);
        } else if (mo >= 11) {
            season_label_result <- "NE " + string(yr);
        } else {
            season_label_result <- "NE " + string(yr - 1);
        }
    }

    // =====================
    // LOAD CURRENT DATE
    // =====================
    action load_current {
        if (length(file_list) > 0) {
            curr_tif <- file_list[current_index];
            fff <- field(curr_tif);
            current_day <- valid_dates[current_index];

            // Season
            int mo <- int(copy_between(current_day, 5, 7));
            if (mo >= 5 and mo <= 10) {
                current_season <- "SW";
                season_color <- rgb(30, 120, 255);
            } else {
                current_season <- "NE";
                season_color <- rgb(255, 60, 60);
            }

            do calc_indicators;
            do calc_sliding_c;
            do save_history;
        }
    }

    // =====================
    // CALCULATE L0, L1, L2, C + Δd
    // =====================
    action calc_indicators {
        current_dd <- [];
        float s1 <- 0.0;
        float s2 <- 0.0;
        int s0 <- 0;

        loop mk from: 1 to: n_transects {
            float dd <- 0.0;
            if (baseline contains_key mk and csv_dist contains_key mk) {
                if (csv_dist[mk] contains_key current_day) {
                    dd <- csv_dist[mk][current_day] - baseline[mk];
                }
            }
            current_dd <- current_dd + [dd];
            s1 <- s1 + abs(dd);
            s2 <- s2 + dd ^ 2;
            if (abs(dd) > l0_threshold) { s0 <- s0 + 1; }
        }

        current_L1 <- s1;
        current_L2 <- sqrt(s2);
        current_L0 <- 100.0 * s0 / n_transects;
        current_C <- (s1 > 0) ? (current_L2 / s1) : 0.0;
    }

    // =====================
    // SLIDING WINDOW C
    // =====================
    action calc_sliding_c {
        current_c_local <- [];
        int hw <- int(window_size / 2);

        loop i from: 0 to: n_transects - 1 {
            int ws <- max(0, i - hw);
            int we <- min(n_transects - 1, i + hw);
            float lc1 <- 0.0;
            float lc2 <- 0.0;

            loop j from: ws to: we {
                float d <- current_dd[j];
                lc1 <- lc1 + abs(d);
                lc2 <- lc2 + d ^ 2;
            }

            float c_val <- (lc1 > 0) ? (sqrt(lc2) / lc1) : 0.0;
            current_c_local <- current_c_local + [c_val];
        }
    }

    // =====================
    // SAVE HISTORY ON SEASON CHANGE
    // =====================
    action save_history {
        do compute_season_label(current_day);
        string lbl <- season_label_result;
        if (lbl != prev_label and prev_label != "" and length(current_c_local) = n_transects) {
            // Save previous season curve
            hist_curves <- hist_curves + [current_c_local collect each];
            hist_labels <- hist_labels + [prev_label];
            if (copy_between(prev_label, 0, 2) = "NE") {
                hist_colors <- hist_colors + [rgb(255, 60, 60, 100)];
            } else {
                hist_colors <- hist_colors + [rgb(30, 120, 255, 100)];
            }
            // Keep max 30 history curves
            if (length(hist_curves) > 30) {
                remove index: 0 from: hist_curves;
                remove index: 0 from: hist_labels;
                remove index: 0 from: hist_colors;
            }
        }
        prev_label <- lbl;
    }

    reflex autoplay when: length(file_list) > 0 {
        current_index <- cycle mod length(file_list);
        do load_current;
    }
}

// =====================
// SPECIES
// =====================
species transect {
    string name <- string(self);
    aspect base {
        draw shape color: #black width: 2;
    }
}

species shoreline {
    string day <- "";

    aspect base_dynamic {
        if (day = current_day) {
            draw self.shape color: season_color border: season_color width: 15;
        }
    }

    aspect base_fixed {
        if (day = first_date) {
            draw self.shape color: #yellow border: #yellow width: 15;
        }
    }
}

// =====================
// EXPERIMENT
// =====================
experiment main type: gui {
    output {
        layout #split;

        // === Part 1: Ảnh vệ tinh + Shoreline gốc (vàng) ===
        display "1_Satellite" type: 2d {
            mesh first_fff color: first_fff.bands scale: 1 triangulation: true smooth: 4;
            species transect aspect: base;
            species shoreline aspect: base_fixed;
            overlay position: {10, -10} size: {200, 25} background: rgb(0,0,0,0) {
                draw "BASELINE: " + first_date at: {5, 20} color: #yellow font: font("Arial", 16, #bold);
            }
        }

        // === Part 2: Shoreline theo mùa (đỏ=NE, xanh=SW) ===
        display "2_Seasonal" type: 2d {
            mesh fff color: fff.bands scale: 1 triangulation: true smooth: 4;
            species transect aspect: base;
            species shoreline aspect: base_dynamic;
            overlay position: {10, -10} size: {300, 25} background: rgb(0,0,0,0) {
                if (length(file_list) > 0) {
                    draw current_season + " | " + current_day + " (" + string(current_index + 1) + "/" + string(length(file_list)) + ")"
                        at: {5, 20} color: season_color font: font("Arial", 16, #bold);
                }
            }
        }

        // === Part 3: Pie L0 (left) + L1&L2 (right) ===
        display Indicator_Dashboard {
            // Pie L0 — left site
            chart "L0 (%)" type: pie 
                size: {0.45, 0.92} position: {0.02, 0.04}
                background: #white {
                data "Changed" value: current_L0 color: #red;
                data "Stable" value: (100.0 - current_L0) color: #green;
            }

            // L1 & L2 — right site
            chart "L1 & L2" type: series
                size: {0.48, 0.92} position: {0.50, 0.04}
                background: #white axes: #black
                x_label: "Time" y_label: "m" {
                data "L1" value: current_L1 color: #green marker: false style: line thickness: 2;
                data "L2" value: current_L2 color: #blue marker: false style: line thickness: 2;
            }
        }

        // === Part 4: C = L2/L1 ===
        display Indicator_Chart {
            chart "C = L2/L1" type: series 
                size: {0.98, 0.92} position: {0.01, 0.04}
                background: #white axes: #black
                x_label: "Time Step" y_label: "C" {
                data "C" value: current_C color: #red marker: false style: line thickness: 2;
                data "C min" value: 1.0 / sqrt(229.0) color: rgb(180,180,180) marker: false style: line thickness: 1;
            }
        }
    }
}
