DROP VIEW IF EXISTS populated_strings CASCADE;
CREATE OR REPLACE VIEW populated_strings AS
SELECT strings.*, string_matches.matches as "matches", string_tags.tags as "tags"
FROM strings
         INNER JOIN (SELECT strings.id     as "string_id",
                            COALESCE(json_agg(string_matches) filter ( where string_matches.string_id is not null ),
                                     '[]') as "matches"
                     FROM strings
                              LEFT JOIN string_matches ON strings.id = string_matches.string_id
                     GROUP BY strings.id) string_matches ON string_matches.string_id = strings.id
         INNER JOIN (SELECT strings.id     as "string_id",
                            COALESCE(json_agg(string_tags) filter ( where string_tags.string_id is not null ),
                                     '[]') as "tags"
                     FROM strings
                              LEFT JOIN string_tags on strings.id = string_tags.string_id
                     GROUP BY strings.id) string_tags ON string_tags.string_id = strings.id;

DROP VIEW IF EXISTS aggregated_strings CASCADE;
CREATE OR REPLACE VIEW aggregated_strings AS
SELECT analyses.id as analysis_id, COALESCE(JSON_AGG(swmat) FILTER (WHERE swmat.id IS NOT NULL), '[]') as string_data
FROM analyses
         LEFT JOIN populated_strings swmat on analyses.id = swmat.analysis_id
GROUP BY analyses.id;

DROP VIEW IF EXISTS populated_sections CASCADE;
CREATE OR REPLACE VIEW populated_sections AS
SELECT sections.*, TO_JSON(section_characteristics) as "characteristics"
FROM (SELECT sections.*, TO_JSON(ARRAY_REMOVE(ARRAY_AGG(section_hashes), NULL)) AS hashes
      FROM sections
               LEFT JOIN section_hashes ON sections.id = section_hashes.section_id
      GROUP BY sections.id) sections
         INNER JOIN section_characteristics
                    ON sections.id = section_characteristics.section_id;

DROP VIEW IF EXISTS aggregated_sections CASCADE;
CREATE OR REPLACE VIEW aggregated_sections AS
SELECT analyses.id as analysis_id, COALESCE(json_agg(ps) filter (where ps.id is not null), '[]') as section_data
FROM analyses
         LEFT JOIN populated_sections ps on analyses.id = ps.analysis_id
GROUP BY analyses.id;

DROP VIEW IF EXISTS populated_files CASCADE;
CREATE OR REPLACE VIEW populated_files AS
SELECT files.*, COALESCE(json_agg(file_hashes) FILTER ( WHERE file_hashes.id is not null ), '[]') AS "hashes"
FROM files
         INNER JOIN file_hashes ON files.id = file_hashes.file_id
GROUP BY files.id;

DROP VIEW IF EXISTS populated_capa_nodes CASCADE;
CREATE OR REPLACE VIEW populated_capa_nodes AS
SELECT capa_nodes.*,
       COALESCE(json_agg(capa_node_locations) FILTER (WHERE capa_node_locations.id IS NOT NULL), '[]') as "locations"
FROM capa_nodes
         LEFT JOIN capa_node_locations ON capa_nodes.id = capa_node_locations.capa_node_id
GROUP BY capa_nodes.id;

DROP VIEW IF EXISTS populated_capa_matches CASCADE;
CREATE OR REPLACE VIEW populated_capa_matches AS
SELECT capa_matches.*, COALESCE(json_agg(pcn) FILTER (WHERE pcn.id IS NOT NULL), '[]') as "nodes"
FROM capa_matches
         LEFT JOIN populated_capa_nodes pcn on capa_matches.id = pcn.capa_match_id
GROUP BY capa_matches.id;

DROP VIEW IF EXISTS populated_capa_entries CASCADE;
CREATE OR REPLACE VIEW populated_capa_entries AS
SELECT capa_entries.*,
       COALESCE(json_agg(populated_capa_matches) FILTER (WHERE populated_capa_matches.id IS NOT NULL),
                '[]') as "matches"
FROM capa_entries
         LEFT JOIN populated_capa_matches on capa_entries.id = populated_capa_matches.capa_entry_id
GROUP BY capa_entries.id;

DROP VIEW IF EXISTS aggregated_capa_entries CASCADE;
CREATE OR REPLACE VIEW aggregated_capa_entries AS
SELECT analyses.id                                                     as analysis_id,
       COALESCE(json_agg(pce) FILTER (WHERE pce.id IS NOT NULL), '[]') AS "capa_entry_data"
FROM analyses
         LEFT JOIN populated_capa_entries pce on analyses.id = pce.analysis_id
GROUP BY analyses.id;

DROP VIEW IF EXISTS aggregated_packers CASCADE;
CREATE OR REPLACE VIEW aggregated_packers AS
SELECT analyses.id                                                                        as analysis_id,
       COALESCE(json_agg(packers) FILTER ( WHERE packers.analysis_id IS NOT NULL ), '[]') AS "packer_entry_data"
FROM analyses
         LEFT JOIN packers on packers.analysis_id = analyses.id
GROUP BY analyses.id;

DROP VIEW IF EXISTS full_analyses CASCADE;
CREATE OR REPLACE VIEW full_analyses AS
SELECT analyses.*,
       TO_JSON(basic_information)                                                 basic_information,
       TO_JSON(file_headers)                                                      file_header,
       TO_JSON(optional_headers)                                                  optional_header,
       TO_JSON(populated_files)                                                   file,
       COALESCE(TO_JSON(imports.import_data), TO_JSON(ARRAY []::record[]))     AS imports,
       COALESCE(TO_JSON(exports.export_data), TO_JSON(ARRAY []::record[]))     AS exports,
       COALESCE(TO_JSON(resources.resource_data), TO_JSON(ARRAY []::record[])) AS resources,
       aggregated_strings.string_data                                          as strings,
       aggregated_sections.section_data                                        AS sections,
       ace.capa_entry_data                                                     AS capa,
       ap.packer_entry_data                                                    as packers
FROM analyses
         -- file
         INNER JOIN populated_files ON populated_files.id = analyses.file_id
-- basic information
         INNER JOIN basic_information ON analyses.id = basic_information.analysis_id
-- file header and characteristics
         INNER JOIN (SELECT file_headers.*, TO_JSON(characteristics) characteristics
                     FROM file_headers
                              INNER JOIN file_header_characteristics "characteristics"
                                         ON "characteristics".analysis_id = "file_headers".analysis_id) file_headers
                    ON analyses.id = file_headers.analysis_id
-- optional header and characteristics
         INNER JOIN (SELECT optional_headers.*, TO_JSON(characteristics) dll_characteristics
                     FROM optional_headers
                              INNER JOIN optional_header_dll_characteristics "characteristics"
                                         ON "characteristics".analysis_id = "optional_headers".analysis_id) optional_headers
                    ON analyses.id = optional_headers.analysis_id
-- imports
         LEFT JOIN (SELECT analysis_id, ARRAY_AGG(imports) AS import_data
                    FROM imports
                    GROUP BY analysis_id) imports ON imports.analysis_id = analyses.id
-- exports
         LEFT JOIN (SELECT analysis_id, ARRAY_AGG(exports) AS export_data
                    FROM exports
                    GROUP BY analysis_id) exports ON exports.analysis_id = analyses.id
-- resources
         LEFT JOIN (SELECT analysis_id, json_agg(resources) AS resource_data
                    FROM (SELECT resources.*, json_agg("resource_hashes") AS "hashes"
                          FROM resources
                                   INNER JOIN resource_hashes ON resources.id = resource_hashes.resource_id
                          GROUP BY resources.id) resources
                    GROUP BY analysis_id) resources ON resources.analysis_id = analyses.id
-- strings
         INNER JOIN aggregated_strings
                    ON analyses.id = aggregated_strings.analysis_id
-- sections
         INNER JOIN aggregated_sections
                    ON aggregated_sections.analysis_id = analyses.id
-- capa data
         INNER JOIN aggregated_capa_entries ace on analyses.id = ace.analysis_id
-- packer detection
         INNER JOIN aggregated_packers ap on analyses.id = ap.analysis_id
WHERE state = 'complete';

SELECT *
FROM full_analyses
WHERE id = 1;

SELECT analyses.id                                                                        as analysis_id,
       COALESCE(json_agg(packers) FILTER ( WHERE packers.analysis_id IS NOT NULL ), '[]') AS "packer_entry_data"
FROM analyses
         LEFT JOIN packers on packers.analysis_id = analyses.id
GROUP BY analyses.id