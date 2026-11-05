package pl.signarail.api.web;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import pl.signarail.api.db.LayoutRepository;
import pl.signarail.api.model.ApiModels.DccCommand;
import pl.signarail.api.model.ApiModels.LayoutCourse;
import pl.signarail.api.model.ApiModels.PowerBudget;
import pl.signarail.api.model.ApiModels.TrackBlock;

@RestController
@RequestMapping("/api/layout")
@Validated
public class LayoutController {

    private final LayoutRepository repository;

    public LayoutController(LayoutRepository repository) {
        this.repository = repository;
    }

    @PostMapping("/courses/{id}/prepare")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @Transactional
    public void prepare(@PathVariable long id) {
        repository.prepare(id);
    }

    @PostMapping("/courses/{id}/start")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @Transactional
    public void start(@PathVariable long id) {
        repository.start(id);
    }

    @GetMapping("/courses")
    public List<LayoutCourse> courses() {
        return repository.courses();
    }

    @GetMapping("/blocks")
    public List<TrackBlock> blocks() {
        return repository.blocks();
    }

    @GetMapping("/commands")
    public List<DccCommand> commands(@RequestParam(defaultValue = "20") @Min(1) @Max(200) int limit) {
        return repository.commands(limit);
    }

    @GetMapping("/power")
    public PowerBudget power() {
        return repository.power();
    }
}
