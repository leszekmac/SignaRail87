CREATE OR REPLACE PACKAGE ut_h0_dcc AS
    --%suite(Ramki DCC wg NMRA S-9.2)

    --%test(Adres krotki, 128 krokow, jazda w przod)
    PROCEDURE predkosc_adres_krotki;
    --%test(Adres dlugi koduje sie na dwoch bajtach)
    PROCEDURE predkosc_adres_dlugi;
    --%test(Krok zero to zwykly stop, nie stop awaryjny)
    PROCEDURE krok_zero_to_stop;
    --%test(Jazda wstecz zeruje bit kierunku)
    PROCEDURE jazda_wstecz;
    --%test(Predkosc w km/h skaluje sie do v_max lokomotywy)
    PROCEDURE skalowanie_kmh;
    --%test(Predkosc powyzej v_max jest przycinana do kroku 126)
    PROCEDURE przyciecie_vmax;
    --%test(Grupa funkcji 1: F0 i F1)
    PROCEDURE funkcje;
    --%test(Rozjazd: adres akcesorium z negacja gornych bitow)
    PROCEDURE rozjazd;
    --%test(Stop awaryjny rozgloszeniowy)
    PROCEDURE stop_awaryjny;
    --%test(Postac bitowa: preambula, bity startu, bit konca)
    PROCEDURE postac_bitowa;
    --%test(Krok poza zakresem jest odrzucany)
    --%throws(-20001)
    PROCEDURE krok_poza_zakresem;
    --%test(Adres poza zakresem jest odrzucany)
    --%throws(-20001)
    PROCEDURE adres_poza_zakresem;
END ut_h0_dcc;
/
CREATE OR REPLACE PACKAGE BODY ut_h0_dcc AS
    PROCEDURE predkosc_adres_krotki IS
    BEGIN
        ut.expect(pkg_h0_controller.ramka_predkosci(3, 60)).to_equal('03 3F BD 81');
    END;
    PROCEDURE predkosc_adres_dlugi IS
    BEGIN
        ut.expect(pkg_h0_controller.ramka_predkosci(1209, 0, 'T')).to_equal('C4 B9 3F 00 42');
    END;
    PROCEDURE krok_zero_to_stop IS
    BEGIN
        ut.expect(pkg_h0_controller.ramka_predkosci(3, 0)).to_equal('03 3F 80 BC');
    END;
    PROCEDURE jazda_wstecz IS
    BEGIN
        ut.expect(pkg_h0_controller.ramka_predkosci(3, 60, 'T')).to_equal('03 3F 3D 01');
    END;
    PROCEDURE skalowanie_kmh IS
    BEGIN
        -- EU07: v_max 125 km/h; 62.5 km/h = krok 63.
        ut.expect(pkg_h0_controller.wygeneruj_ramke_dcc(2, 62.5))
            .to_equal(pkg_h0_controller.ramka_predkosci(7, 63));
    END;
    PROCEDURE przyciecie_vmax IS
    BEGIN
        ut.expect(pkg_h0_controller.wygeneruj_ramke_dcc(2, 400))
            .to_equal(pkg_h0_controller.ramka_predkosci(7, 126));
    END;
    PROCEDURE funkcje IS
    BEGIN
        ut.expect(pkg_h0_controller.ramka_funkcji(3, TRUE, TRUE)).to_equal('03 91 92');
        ut.expect(pkg_h0_controller.ramka_funkcji(3, FALSE, FALSE)).to_equal('03 80 83');
    END;
    PROCEDURE rozjazd IS
    BEGIN
        ut.expect(pkg_h0_controller.ramka_rozjazdu(11, 'PROSTO')).to_equal('83 FD 7E');
        ut.expect(pkg_h0_controller.ramka_rozjazdu(11, 'ZWROTNA')).to_equal('83 FC 7F');
        -- Adres 2044: dekoder 511, gorne bity 111 -> w negacji 000.
        ut.expect(pkg_h0_controller.ramka_rozjazdu(2044, 'PROSTO')).to_equal('BF 8F 30');
    END;
    PROCEDURE stop_awaryjny IS
    BEGIN
        ut.expect(pkg_h0_controller.ramka_stopu_awaryjnego).to_equal('00 71 71');
    END;
    PROCEDURE postac_bitowa IS
    BEGIN
        ut.expect(pkg_h0_controller.ramka_na_bity('03 91 92'))
            .to_equal('11111111111111' || '0' || '00000011' || '0' || '10010001' || '0' || '10010010' || '1');
    END;
    PROCEDURE krok_poza_zakresem IS
        v VARCHAR2(40);
    BEGIN
        v := pkg_h0_controller.ramka_predkosci(3, 127);
    END;
    PROCEDURE adres_poza_zakresem IS
        v VARCHAR2(40);
    BEGIN
        v := pkg_h0_controller.ramka_predkosci(10240, 1);
    END;
END ut_h0_dcc;
/
