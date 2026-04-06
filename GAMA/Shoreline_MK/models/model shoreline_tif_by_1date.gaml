/**
 * Multi-Norm Shoreline Dynamics
 * © 2026 [Author Name]. Confidential.
 */
model tif_shoreline_multinorm

global {
    file shoreline_file <- file("../includes/Shoreline_MK_v2.shp");
    file transect_file  <- file("../includes/transects.shp");
    directory tif_dir   <- directory("../includes/Tif_RGBA/");
    directory csv_dir   <- directory("../includes/day1/");

    list<string> tif_names <- list<string>(tif_dir.contents) where (length(each) >= 14 and copy_between(each, length(each)-4, length(each)) = ".tif");
    list<grid_file> file_list <- [];  list<string> valid_dates <- [];
    int current_index <- 0;
    grid_file curr_tif;   field fff;       string current_day <- "";
    grid_file fixed_tif;  field first_fff; string first_date <- "";
    grid_file ref_tif <- grid_file("../includes/Tif_RGBA/2022-07-26-03-23-46_S2_49PBT_MYKHE_RGBN.tif");
    geometry shape <- envelope(ref_tif);

    int n_transects <- 229;  float l0_threshold <- 2.0;
    map<int, map<string, float>> csv_dist;
    map<int, float> baseline;
    list<float> current_dd <- [];
    string current_season <- "";  rgb season_color <- #red;
    float current_L0 <- 0.0;  float current_L1 <- 0.0;
    float current_L2 <- 0.0;  float current_C  <- 0.0;
    string prev_label <- "";
    list<geometry> baseline_shapes <- [];

    // Table history
    list<string> table_seasons <- [];
    list<float> table_L0 <- [];  list<float> table_L1 <- [];
    list<float> table_L2 <- [];  list<float> table_C  <- [];

    init {
        create transect from: transect_file;
        create shoreline from: shoreline_file with: [day :: copy_between(replace(string(read("date")), "/", "-"), 0, 10)];
        list<string> sl_dates <- remove_duplicates(shoreline collect each.day);
        loop f over: tif_names where (sl_dates contains copy_between(each, 0, 10)) {
            file_list   <- file_list   + [grid_file(tif_dir.path + "/" + f)];
            valid_dates <- valid_dates + [copy_between(f, 0, 10)];
        }
        ask shoreline { if !(valid_dates contains day) { do die; } }
        if (length(file_list) > 0) {
            first_date <- valid_dates[0];  fixed_tif <- file_list[0];  first_fff <- field(fixed_tif);
            baseline_shapes <- (shoreline where (each.day = first_date)) collect each.shape;
            do load_csv;  do compute_baseline;  do load_current;
        } else {
            fff <- field(matrix<float>([[0.0]]));  first_fff <- fff;
            current_day <- "N/A";  first_date <- "N/A";
        }
    }

    action load_csv {
        loop fname over: list<string>(csv_dir.contents) where (length(each) > 4 and copy_between(each, length(each)-4, length(each)) = ".csv") {
            int p <- fname index_of "MK";
            if (p > -1) {
                int mk <- int(copy_between(fname, p+2, length(fname)-4));
                matrix data <- matrix(csv_file(csv_dir.path + "/" + fname, ","));
                map<string, float> dists;
                loop i from: 1 to: data.rows - 1 {
                    string ds <- string(data[1,i]);
                    if (length(ds) >= 10) { dists[copy_between(ds,0,10)] <- float(data[2,i]); }
                }
                csv_dist[mk] <- dists;
            }
        }
        write "Loaded " + string(length(csv_dist)) + " transect CSV";
    }

    action compute_baseline {
        int yr <- int(copy_between(first_date, 0, 4));
        int mo <- int(copy_between(first_date, 5, 7));
        string s_start;  string s_end;  string s_type;
        if (mo >= 5 and mo <= 10) { s_type <- "SW"; s_start <- string(yr)+"-05"; s_end <- string(yr)+"-11"; }
        else if (mo >= 11)        { s_type <- "NE"; s_start <- string(yr)+"-11"; s_end <- string(yr+1)+"-05"; }
        else                      { s_type <- "NE"; s_start <- string(yr-1)+"-11"; s_end <- string(yr)+"-05"; }
        loop mk from: 1 to: n_transects {
            if (csv_dist contains_key mk) {
                float total <- 0.0;  int cnt <- 0;
                loop dkey over: (csv_dist[mk]).keys {
                    if (dkey >= s_start and dkey < s_end) { total <- total + csv_dist[mk][dkey]; cnt <- cnt + 1; }
                }
                if (cnt > 0) { baseline[mk] <- total / cnt; }
            }
        }
        write "Baseline: " + s_type + " " + string(yr) + " (" + string(length(baseline)) + " transects)";
    }

    string get_season_label (string d) {
        int yr <- int(copy_between(d, 0, 4));  int mo <- int(copy_between(d, 5, 7));
        if (mo >= 5 and mo <= 10) { return "SW " + string(yr); }
        if (mo >= 11)             { return "NE " + string(yr); }
        return "NE " + string(yr - 1);
    }

    action load_current {
        curr_tif <- file_list[current_index];  fff <- field(curr_tif);
        current_day <- valid_dates[current_index];
        int mo <- int(copy_between(current_day, 5, 7));
        if (mo >= 5 and mo <= 10) { current_season <- "SW"; season_color <- rgb(30,120,255); }
        else                      { current_season <- "NE"; season_color <- rgb(255,60,60); }
        do calc_indicators;  do save_history;
    }

    action calc_indicators {
        current_dd <- [];  float s1 <- 0.0;  float s2 <- 0.0;  int s0 <- 0;
        loop mk from: 1 to: n_transects {
            float dd <- 0.0;
            if (baseline contains_key mk and csv_dist contains_key mk and csv_dist[mk] contains_key current_day) {
                dd <- csv_dist[mk][current_day] - baseline[mk];
            }
            current_dd <- current_dd + [dd];
            s1 <- s1 + abs(dd);  s2 <- s2 + dd^2;
            if (abs(dd) > l0_threshold) { s0 <- s0 + 1; }
        }
        current_L1 <- s1;  current_L2 <- sqrt(s2);
        current_L0 <- 100.0 * s0 / n_transects;
        current_C  <- (s1 > 0) ? (current_L2 / s1) : 0.0;
    }

    action save_history {
        string lbl <- get_season_label(current_day);
        if (lbl != prev_label and prev_label != "") {
            table_seasons <- table_seasons + [prev_label];
            table_L0 <- table_L0 + [current_L0];  table_L1 <- table_L1 + [current_L1];
            table_L2 <- table_L2 + [current_L2];  table_C  <- table_C  + [current_C];
            if (length(table_seasons) > 20) { remove index:0 from:table_seasons; remove index:0 from:table_L0; remove index:0 from:table_L1; remove index:0 from:table_L2; remove index:0 from:table_C; }
        }
        prev_label <- lbl;
    }

    reflex autoplay when: length(file_list) > 0 {
        current_index <- cycle mod length(file_list);
        do load_current;
    }
}

species transect { aspect base { draw shape color: #black width: 2; } }
species shoreline {
    string day <- "";
    aspect base_dynamic { if (day = current_day) { draw self.shape color: season_color border: season_color width: 15; } }
}

experiment main type: gui {
    output {
        layout #split;
        display "1_Baseline" type: 2d {
            mesh first_fff color: first_fff.bands scale: 1 triangulation: true smooth: 4;
            species transect aspect: base;
            graphics "baseline" { loop g over: baseline_shapes { draw g color: #yellow border: #yellow width: 15; } }
            overlay position: {10,-10} size: {300,25} background: rgb(0,0,0,0) {
                draw "BASELINE: " + first_date at: {5,20} color: #yellow font: font("Arial",16,#bold);
            }
        }
        display "2_Seasonal" type: 2d {
            mesh fff color: fff.bands scale: 1 triangulation: true smooth: 4;
            species transect aspect: base;
            graphics "current" { loop s over: shoreline { if (s.day = current_day) { draw s.shape color: season_color border: season_color width: 15; } } }
            overlay position: {10,-10} size: {400,25} background: rgb(0,0,0,0) {
                if (length(file_list) > 0) {
                    draw current_season + " | " + current_day + " (" + string(current_index+1) + "/" + string(length(file_list)) + ")"
                        at: {5,20} color: season_color font: font("Arial",16,#bold);
                }
            }
        }
        display Indicator_Dashboard refresh: every(10#cycles) {
            chart "L0 (%)" type: pie style: exploded position: {0, 0} background: #white {
                data "Changed" value: current_L0 color: #red;
                data "Stable"  value: (100.0 - current_L0) color: #green;
            }
            chart "C = L2/L1" type: series position: {1, 0} background: #white {
                data "C" value: current_C color: #red style: line;
                data "C min" value: 1.0 / sqrt(229.0) color: rgb(180,180,180) style: line;
            }
        }
        display Indicator_Table type: 2d background: #white {
            graphics "table" {
                float w <- world.shape.width;  float h <- world.shape.height;
                list<float> cx <- [0, 0.25, 0.55, 0.75, 1];
                draw "MULTI-NORM INDICATORS" at: {w*0.02, h*0.03} color: #black font: font("Arial",18,#bold);
                loop j from: 0 to: 4 { draw ["Season","L0(%)","L1(m)","L2(m)","C"] at j at: {w*cx[j], h*0.10} color: #black font: font("Courier New",13,#bold); }
                draw line({w*0.02, h*0.13}, {w*0.95, h*0.13}) color: #gray;
                rgb cc <- (current_season="NE") ? rgb(220,40,40) : rgb(20,100,220);
                list<string> cv <- [current_season+" (now)", string(current_L0 with_precision 1), string(current_L1 with_precision 1), string(current_L2 with_precision 1), string(current_C with_precision 3)];
                loop j from: 0 to: 4 { draw cv[j] at: {w*cx[j], h*0.18} color: cc font: font("Courier New",12,#bold); }
                draw line({w*0.02, h*0.22}, {w*0.95, h*0.22}) color: #gray;
                loop i from: 0 to: length(table_seasons)-1 {
                    float ry <- h * (0.27 + i * 0.07);
                    rgb rc <- (copy_between(table_seasons[i],0,2)="NE") ? rgb(200,50,50) : rgb(20,90,200);
                    list<string> rv <- [table_seasons[i], string(table_L0[i] with_precision 1), string(table_L1[i] with_precision 1), string(table_L2[i] with_precision 1), string(table_C[i] with_precision 3)];
                    loop j from: 0 to: 4 { draw rv[j] at: {w*cx[j], ry} color: rc font: font("Courier New",11,#plain); }
                }
            }
        }
    }
}
